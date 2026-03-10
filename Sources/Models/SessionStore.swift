import Foundation
import Combine

/// Groups sessions by their iTerm2 profile name, representing a "project".
struct ProjectGroup: Identifiable {
    var id: String { profileName }
    let profileName: String
    var sessions: [ITerm2Bridge.SessionInfo]
    var isExpanded: Bool = true

    var windowIds: Set<String> {
        Set(sessions.map(\.windowId))
    }

    var sessionCount: Int { sessions.count }

    var hasActiveSession: Bool {
        sessions.contains { $0.isActive }
    }
}

/// Observable store that polls iTerm2 and maintains the current state.
@Observable
final class SessionStore {
    var projectGroups: [ProjectGroup] = []
    var isITerm2Running: Bool = false
    var isAPIConnected: Bool = false
    var lastUpdated: Date?

    private let bridge = ITerm2Bridge()
    private var timer: Timer?
    private var pollingInterval: TimeInterval = 2.0
    private var hasCompletedInitialRefresh = false

    /// Low-priority queue for background polling — never blocks user actions
    private var isRefreshing = false
    private let pollQueue = DispatchQueue(label: "com.sessionhub.poll", qos: .userInitiated)
    /// High-priority queue for user-triggered actions — runs immediately
    private let actionQueue = DispatchQueue(label: "com.sessionhub.action", qos: .userInteractive)

    // MARK: - Polling

    func startPolling(interval: TimeInterval = 2.0) {
        pollingInterval = interval
        SHLog.log("[SessionHub] Starting polling (interval: \(interval)s) — no TCC needed")

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Refresh

    func refresh() {
        if !hasCompletedInitialRefresh {
            SHLog.log("[SessionHub] Running initial refresh")
            pollQueue.async { [weak self] in
                self?.performRefresh()
                self?.hasCompletedInitialRefresh = true
            }
            return
        }

        pollQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isRefreshing else {
                SHLog.log("[SessionHub] Skipping refresh — previous poll still running")
                return
            }
            self.performRefresh()
        }
    }

    private func performRefresh() {
        isRefreshing = true

        let running = bridge.isITerm2Running()
        let groups: [ProjectGroup]
        let connected: Bool

        if running {
            connected = bridge.ensureConnected()
            if connected {
                let windows = bridge.fetchSessions()
                if windows.isEmpty {
                    SHLog.log("[SessionHub] iTerm2 API returned no windows")
                } else {
                    SHLog.log("[SessionHub] Found \(windows.count) window(s)")
                }
                groups = Self.groupByProfile(windows: windows)
            } else {
                SHLog.log("[SessionHub] iTerm2 running but API not connected")
                groups = []
            }
        } else {
            SHLog.log("[SessionHub] iTerm2 is not running")
            connected = false
            groups = []
        }

        DispatchQueue.main.async {
            self.isITerm2Running = running
            self.isAPIConnected = connected
            self.projectGroups = groups
            self.lastUpdated = Date()
            self.isRefreshing = false
        }
    }

    // MARK: - Actions (all run on separate high-priority queue)

    func switchToSession(_ session: ITerm2Bridge.SessionInfo) {
        actionQueue.async { [weak self] in
            self?.bridge.switchToSession(sessionId: session.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refresh()
            }
        }
    }

    func createTab(forProfile profile: String, inWindowId windowId: String) {
        actionQueue.async { [weak self] in
            self?.bridge.createTab(withProfile: profile, inWindowId: windowId)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.refresh()
            }
        }
    }

    func createWindow(withProfile profile: String) {
        actionQueue.async { [weak self] in
            self?.bridge.createWindow(withProfile: profile)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.refresh()
            }
        }
    }

    func renameSession(_ session: ITerm2Bridge.SessionInfo, to name: String) {
        actionQueue.async { [weak self] in
            self?.bridge.renameSession(sessionId: session.id, name: name)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.refresh()
            }
        }
    }

    // MARK: - Helpers

    private static func groupByProfile(windows: [ITerm2Bridge.WindowInfo]) -> [ProjectGroup] {
        var grouped: [String: [ITerm2Bridge.SessionInfo]] = [:]

        for window in windows {
            for tab in window.tabs {
                for session in tab.sessions {
                    grouped[session.profileName, default: []].append(session)
                }
            }
        }

        return grouped.map { profileName, sessions in
            ProjectGroup(profileName: profileName, sessions: sessions)
        }.sorted { $0.profileName.lowercased() < $1.profileName.lowercased() }
    }
}
