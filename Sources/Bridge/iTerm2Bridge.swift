import Foundation
import AppKit

/// Communicates with iTerm2 via NSAppleScript (in-process, fast) to list, switch, create, and rename sessions.
final class ITerm2Bridge {

    // MARK: - Data Types

    struct WindowInfo: Identifiable {
        let id: Int
        let name: String
        var tabs: [TabInfo]
    }

    struct TabInfo: Identifiable {
        var id: String { "\(windowId)-\(index)" }
        let windowId: Int
        let index: Int
        let title: String
        var sessions: [SessionInfo]
    }

    struct SessionInfo: Identifiable {
        let id: String
        let windowId: Int
        let tabIndex: Int
        let sessionIndex: Int
        let profileName: String
        let name: String
        let isActive: Bool
        let tty: String
    }

    // MARK: - Check if iTerm2 is running (no AppleScript needed)

    func isITerm2Running() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first != nil
    }

    // MARK: - Fetch All Sessions

    /// Fetches the complete hierarchy of windows, tabs, and sessions from iTerm2.
    func fetchSessions() -> [WindowInfo] {
        guard isITerm2Running() else { return [] }

        let script = """
        tell application "iTerm2"
            set outputLines to {}
            set activeSessId to ""

            try
                set activeSess to current session of current tab of current window
                set activeSessId to unique id of activeSess
            end try

            repeat with w in windows
                set winId to id of w
                set winName to name of w
                set tabIdx to 0
                repeat with t in tabs of w
                    set sessIdx to 0
                    repeat with s in sessions of t
                        set profName to profile name of s
                        set sessName to name of s
                        set sessId to unique id of s
                        set sessTty to tty of s
                        set isAct to "0"
                        if sessId is equal to activeSessId then
                            set isAct to "1"
                        end if
                        set end of outputLines to ((winId as text) & "§" & winName & "§" & (tabIdx as text) & "§" & (sessIdx as text) & "§" & profName & "§" & sessName & "§" & sessId & "§" & sessTty & "§" & isAct)
                        set sessIdx to sessIdx + 1
                    end repeat
                    set tabIdx to tabIdx + 1
                end repeat
            end repeat

            set AppleScript's text item delimiters to linefeed
            return outputLines as text
        end tell
        """

        let output = runAppleScript(script)
        return parseSessionOutput(output)
    }

    // MARK: - Switch Focus

    /// Switches iTerm2 focus to a specific tab in a specific window.
    func switchToSession(windowId: Int, tabIndex: Int) {
        let script = """
        tell application "iTerm2"
            activate
            set targetWindow to window id \(windowId)
            select targetWindow
            tell targetWindow
                select tab \(tabIndex + 1)
            end tell
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - Create

    /// Creates a new tab with the given profile in the specified window.
    func createTab(inWindowId windowId: Int, withProfile profile: String) {
        let escapedProfile = profile.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm2"
            tell window id \(windowId)
                create tab with profile "\(escapedProfile)"
            end tell
        end tell
        """
        runAppleScript(script)
    }

    /// Creates a new window with the given profile.
    func createWindow(withProfile profile: String) {
        let escapedProfile = profile.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm2"
            create window with profile "\(escapedProfile)"
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - Rename

    /// Renames a session (the name shown in the tab).
    func renameSession(windowId: Int, tabIndex: Int, sessionIndex: Int, name: String) {
        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm2"
            tell window id \(windowId)
                tell session \(sessionIndex + 1) of tab \(tabIndex + 1)
                    set name to "\(escapedName)"
                end tell
            end tell
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - Private Helpers

    @discardableResult
    private func runAppleScript(_ source: String) -> String {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }

    private func parseSessionOutput(_ output: String) -> [WindowInfo] {
        guard !output.isEmpty else { return [] }

        var windowsDict: [Int: WindowInfo] = [:]

        for line in output.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "§")
            guard parts.count >= 9 else { continue }

            let winId = Int(parts[0]) ?? 0
            let winName = parts[1]
            let tabIdx = Int(parts[2]) ?? 0
            let sessIdx = Int(parts[3]) ?? 0
            let profileName = parts[4]
            let sessName = parts[5]
            let sessId = parts[6]
            let tty = parts[7]
            let isActive = parts[8] == "1"

            let session = SessionInfo(
                id: sessId,
                windowId: winId,
                tabIndex: tabIdx,
                sessionIndex: sessIdx,
                profileName: profileName,
                name: sessName,
                isActive: isActive,
                tty: tty
            )

            if windowsDict[winId] == nil {
                windowsDict[winId] = WindowInfo(id: winId, name: winName, tabs: [])
            }

            if let existingTabIndex = windowsDict[winId]?.tabs.firstIndex(where: { $0.index == tabIdx }) {
                windowsDict[winId]?.tabs[existingTabIndex].sessions.append(session)
            } else {
                let tab = TabInfo(
                    windowId: winId,
                    index: tabIdx,
                    title: "Tab \(tabIdx + 1)",
                    sessions: [session]
                )
                windowsDict[winId]?.tabs.append(tab)
            }
        }

        return Array(windowsDict.values).sorted { $0.id < $1.id }
    }
}
