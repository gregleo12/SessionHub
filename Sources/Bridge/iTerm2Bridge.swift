import Foundation
import AppKit

/// Simple file logger that always works regardless of build config
enum SHLog {
    private static let logFile: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sessionhub.log")
        // Truncate on launch
        try? "".write(to: url, atomically: true, encoding: .utf8)
        return url
    }()

    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        NSLog("[SessionHub] %@", message)
        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }
}

/// Communicates with iTerm2 via its Python API (WebSocket + protobuf).
/// No Apple Events or TCC permission required.
final class ITerm2Bridge {

    // MARK: - Data Types

    struct WindowInfo: Identifiable {
        let id: String       // iTerm2 window_id string (was Int for AppleScript)
        let name: String
        let number: Int32
        var tabs: [TabInfo]
    }

    struct TabInfo: Identifiable {
        var id: String { tabId }
        let tabId: String
        let windowId: String
        let index: Int
        var sessions: [SessionInfo]
    }

    struct SessionInfo: Identifiable {
        let id: String          // unique_identifier from iTerm2
        let windowId: String
        let tabId: String
        let tabIndex: Int
        let sessionIndex: Int
        let profileName: String
        let name: String
        let isActive: Bool
    }

    // MARK: - API Client

    private let apiClient = ITerm2APIClient()
    private var apiConnected = false

    /// Ensure we're connected to the API. Returns true if connected.
    func ensureConnected() -> Bool {
        if apiClient.connected { return true }

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        apiClient.connect { connected in
            success = connected
            semaphore.signal()
        }

        semaphore.wait()
        apiConnected = success

        if !success {
            SHLog.log("[Bridge] Failed to connect to iTerm2 API. Is Python API enabled?")
        }
        return success
    }

    // MARK: - Check if iTerm2 is running (no API needed)

    func isITerm2Running() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first != nil
    }

    // MARK: - Fetch All Sessions

    func fetchSessions() -> [WindowInfo] {
        guard isITerm2Running() else {
            SHLog.log("fetchSessions: iTerm2 not running")
            return []
        }

        guard ensureConnected() else {
            SHLog.log("fetchSessions: not connected to API")
            return []
        }

        SHLog.log("fetchSessions: querying via API")

        let parsedWindows = apiClient.listSessions()
        if parsedWindows.isEmpty {
            SHLog.log("fetchSessions: no windows returned")
            return []
        }

        // Now fetch profile names for all sessions
        var windows: [WindowInfo] = []

        for pw in parsedWindows {
            var tabs: [TabInfo] = []

            for (tabIdx, pt) in pw.tabs.enumerated() {
                var sessions: [SessionInfo] = []

                for (sessIdx, ps) in pt.sessions.enumerated() {
                    // Fetch profile name for this session
                    let profileName = apiClient.getProfileName(sessionId: ps.uniqueId) ?? "Default"

                    let session = SessionInfo(
                        id: ps.uniqueId,
                        windowId: pw.windowId,
                        tabId: pt.tabId,
                        tabIndex: tabIdx,
                        sessionIndex: sessIdx,
                        profileName: profileName,
                        name: ps.title,
                        isActive: false  // Will determine active session separately
                    )
                    sessions.append(session)
                }

                let tab = TabInfo(
                    tabId: pt.tabId,
                    windowId: pw.windowId,
                    index: tabIdx,
                    sessions: sessions
                )
                tabs.append(tab)
            }

            let window = WindowInfo(
                id: pw.windowId,
                name: "Window \(pw.windowNumber)",
                number: pw.windowNumber,
                tabs: tabs
            )
            windows.append(window)
        }

        SHLog.log("fetchSessions: found \(windows.count) window(s)")
        return windows
    }

    // MARK: - Switch Focus

    func switchToSession(sessionId: String) {
        guard ensureConnected() else { return }

        let success = apiClient.activate(sessionId: sessionId)
        if !success {
            SHLog.log("[Bridge] Failed to activate session \(sessionId)")
        }

        // Also bring iTerm2 to front
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first {
            app.activate()
        }
    }

    // MARK: - Create

    func createTab(withProfile profile: String, inWindowId windowId: String) {
        guard ensureConnected() else { return }
        _ = apiClient.createTab(profileName: profile, windowId: windowId)
    }

    func createWindow(withProfile profile: String) {
        guard ensureConnected() else { return }
        _ = apiClient.createTab(profileName: profile, windowId: nil)
    }

    // MARK: - Rename

    func renameSession(sessionId: String, name: String) {
        guard ensureConnected() else { return }
        _ = apiClient.renameSession(sessionId: sessionId, name: name)
    }
}
