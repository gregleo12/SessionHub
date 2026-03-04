# SessionHub

A lightweight macOS menu bar app that organizes your iTerm2 sessions by project.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## The Problem

When working on multiple projects with several terminal sessions each, iTerm2 windows and tabs pile up fast. There's no easy way to see which session belongs to which project or quickly jump to the right one.

## The Solution

SessionHub lives in your menu bar and shows all your iTerm2 sessions **grouped by profile**. One click switches you to the right window and tab.

### How it works

1. Set up an **iTerm2 profile** per project (Settings → Profiles), each with its own working directory
2. SessionHub automatically groups your open sessions by profile name
3. Click any session in the dropdown to instantly switch to it

### Features

- **Menu bar dropdown** — always one click away
- **Sessions grouped by project** (iTerm2 profile)
- **Click to switch** — activates the correct window and tab
- **Right-click to rename** sessions
- **Create new tabs** per project with the ⊕ button
- **Active session indicator** — green dot shows where you are
- **Auto-refresh** — polls every 2 seconds in the background
- **Launch at login** — always available when you need it

## Install

### From source

```bash
git clone https://github.com/gregleo12/SessionHub.git
cd SessionHub
./build.sh
cp -r build/SessionHub.app /Applications/
open /Applications/SessionHub.app
```

### Requirements

- macOS 14 (Sonoma) or later
- iTerm2
- On first launch, grant Automation permission when prompted

## Setup

For best results, create an iTerm2 profile per project:

1. Open **iTerm2 → Settings → Profiles**
2. Click **+** to create a new profile
3. Set the **Name** to your project name (e.g., "MyApp")
4. Under **Working Directory**, select **Directory** and enter your project path
5. Optionally set a **Tab Color** (Colors tab) for visual identification

SessionHub will automatically group all sessions by their profile name.

## Launch at Login

To have SessionHub start automatically:

```bash
cp com.sessionhub.app.plist ~/Library/LaunchAgents/
```

Or add it manually via System Settings → General → Login Items.

## How It's Built

- **SwiftUI** `MenuBarExtra` for the menu bar interface
- **AppleScript** via `osascript` to communicate with iTerm2
- **Swift Package Manager** for the build system
- Separate dispatch queues for polling (low priority) and user actions (high priority)

The entire app is ~800 lines of Swift. Built in a single Claude Code session.

## Contributing

PRs welcome! Some ideas for future improvements:

- [ ] Floating sidebar panel (always-visible mode)
- [ ] Search/filter sessions
- [ ] Show git branch per session
- [ ] Keyboard shortcuts for switching (⌘1-9)
- [ ] Session status indicators (idle vs. active)
- [ ] Custom app icon

## License

MIT
