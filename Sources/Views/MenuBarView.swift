import SwiftUI

/// The main content view displayed in the menu bar dropdown.
struct MenuBarView: View {
    @Bindable var store: SessionStore
    @State private var renamingSession: ITerm2Bridge.SessionInfo?
    @State private var renameText: String = ""
    @State private var hoveredSessionId: String?
    @State private var showNewSessionMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView

            Divider()

            if !store.isITerm2Running {
                notRunningView
            } else if store.projectGroups.isEmpty {
                emptyView
            } else {
                // Session list
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(store.projectGroups) { group in
                            projectGroupView(group)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 400)
            }

            Divider()

            // Footer actions
            footerView
        }
        .frame(width: 280)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text("SessionHub")
                .font(.headline)
            Spacer()
            if let updated = store.lastUpdated {
                Text(updated, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Project Group

    private func projectGroupView(_ group: ProjectGroup) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            // Group header
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(colorForProfile(group.profileName))

                Text(group.profileName)
                    .font(.system(.subheadline, weight: .semibold))

                Text("\(group.sessionCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())

                Spacer()

                // Add tab button
                Button {
                    addTabToProject(group)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New tab in \(group.profileName)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            // Sessions in this group
            ForEach(group.sessions) { session in
                sessionRow(session, profileName: group.profileName)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Session Row

    private func sessionRow(_ session: ITerm2Bridge.SessionInfo, profileName: String) -> some View {
        Group {
            if renamingSession?.id == session.id {
                // Inline rename field
                HStack(spacing: 6) {
                    TextField("Session name", text: $renameText, onCommit: {
                        store.renameSession(session, to: renameText)
                        renamingSession = nil
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption))

                    Button("OK") {
                        store.renameSession(session, to: renameText)
                        renamingSession = nil
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 2)
            } else {
                Button {
                    store.switchToSession(session)
                } label: {
                    HStack(spacing: 6) {
                        // Active indicator
                        Circle()
                            .fill(session.isActive ? Color.green : Color.clear)
                            .frame(width: 6, height: 6)

                        // Session name
                        Text(displayName(for: session))
                            .font(.system(.caption, weight: session.isActive ? .semibold : .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        // Tab indicator
                        Text("Tab \(session.tabIndex + 1)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .background(
                        hoveredSessionId == session.id
                            ? Color.accentColor.opacity(0.1)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hoveredSessionId = isHovered ? session.id : nil
                }
                .contextMenu {
                    Button("Rename...") {
                        renameText = session.name
                        renamingSession = session
                    }
                    Button("New Tab in \(profileName)") {
                        store.createTab(forProfile: profileName, inWindowId: session.windowId)
                    }
                }
            }
        }
    }

    // MARK: - States

    private var notRunningView: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("iTerm2 is not running")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Launch iTerm2 to see your sessions")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No sessions found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Open a terminal tab in iTerm2")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button {
                store.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func displayName(for session: ITerm2Bridge.SessionInfo) -> String {
        let name = session.name
        // If the session name is just the shell path or empty, use a friendlier name
        if name.isEmpty || name.hasSuffix("zsh") || name.hasSuffix("bash") {
            return "Session \(session.sessionIndex + 1)"
        }
        return name
    }

    private func addTabToProject(_ group: ProjectGroup) {
        // Add a new tab to the first window that has this profile
        if let firstSession = group.sessions.first {
            store.createTab(forProfile: group.profileName, inWindowId: firstSession.windowId)
        } else {
            store.createWindow(withProfile: group.profileName)
        }
    }

    /// Returns a consistent color for a profile name.
    private func colorForProfile(_ name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .cyan, .mint, .indigo, .teal]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}
