import Foundation
import Combine

/// Groups sessions by their iTerm2 profile name, representing a "project".
struct ProjectGroup: Identifiable {
    var id: String { profileName }
    let profileName: String
    var sessions: [ITerm2Bridge.SessionInfo]
    var isExpanded: Bool = true

    var windowIds: Set<Int> {
        Set(sessions.map(\.windowId))
    }

    var sessionCount: Int { sessions.count }

    var hasActiveSession: Bool {
        sessions.contains { $0.isActive }
    }
}

/// Observable store that polls iTerm2 and maintains the current state.
/// All AppleScript calls run on a background queue to keep the UI snappy.
@Observable
final class SessionStore {
    var projectGroups: [ProjectGroup] = []
    var isITerm2Running: Bool = false
    var lastUpdated: Date?

    private let bridge = ITerm2Bridge()
    private var timer: Timer?
    private var pollingInterval: TimeInterval = 2.0
    private let backgroundQueue = DispatchQueue(label: "com.sessionhub.bridge", qos: .userInitiated)

    // MARK: - Polling

    func startPolling(interval: TimeInterval = 2.0) {
        pollingInterval = interval
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
        backgroundQueue.async { [weak self] in
            guard let self else { return }

            let running = self.bridge.isITerm2Running()
            let groups: [ProjectGroup]

            if running {
                let windows = self.bridge.fetchSessions()
                groups = Self.groupByProfile(windows: windows)
            } else {
                groups = []
            }

            DispatchQueue.main.async {
                self.isITerm2Running = running
                self.projectGroups = groups
                self.lastUpdated = Date()
            }
        }
    }

    // MARK: - Actions

    func switchToSession(_ session: ITerm2Bridge.SessionInfo) {
        backgroundQueue.async { [weak self] in
            self?.bridge.switchToSession(windowId: session.windowId, tabIndex: session.tabIndex)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.refresh()
            }
        }
    }

    func createTab(forProfile profile: String, inWindowId windowId: Int) {
        backgroundQueue.async { [weak self] in
            self?.bridge.createTab(inWindowId: windowId, withProfile: profile)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.refresh()
            }
        }
    }

    func createWindow(withProfile profile: String) {
        backgroundQueue.async { [weak self] in
            self?.bridge.createWindow(withProfile: profile)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.refresh()
            }
        }
    }

    func renameSession(_ session: ITerm2Bridge.SessionInfo, to name: String) {
        backgroundQueue.async { [weak self] in
            self?.bridge.renameSession(
                windowId: session.windowId,
                tabIndex: session.tabIndex,
                sessionIndex: session.sessionIndex,
                name: name
            )
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
