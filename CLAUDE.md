# SessionHub — Project Context

## What is SessionHub?

A native **SwiftUI macOS menu bar app** that acts as a companion to iTerm2. It shows all open iTerm2 sessions grouped by profile (project), letting the user quickly switch between them with a click.

## The Problem

When working on multiple projects (FPL, weRate, GridBot, Pingo, etc.) with multiple Claude Code sessions each, iTerm2 windows and tabs pile up. There's no visual way to see which session belongs to which project or quickly jump to the right one.

## How It Works

- **Menu bar icon** — always present, click to see all sessions grouped by project
- **AppleScript bridge** — communicates with iTerm2 via `NSAppleScript` (in-process, fast)
- **Polling** — refreshes session list every 2 seconds on a background thread
- **Click to switch** — clicking a session activates the correct iTerm2 window and tab
- **Right-click** — rename sessions, add new tabs

## Architecture

```
SessionHub (SwiftUI macOS App)
├── Menu Bar Icon + Dropdown       ← primary interface (BUILT - MVP)
│   ├── Project tree (grouped by iTerm2 profile name)
│   ├── Click session → switch iTerm2 focus
│   ├── + New Session button per project
│   └── Right-click to rename
├── Floating Panel (optional)      ← NOT YET BUILT
│   └── Always-visible sidebar, toggle in settings
├── Manager Window                 ← NOT YET BUILT
│   └── Full window for bulk renaming, organizing
└── iTerm2 Bridge (AppleScript)    ← BUILT
    ├── List windows, tabs, sessions, profile names
    ├── Switch focus (window + tab)
    ├── Create new window/tab with profile
    └── Rename sessions
```

## Tech Stack

- **Language:** Swift
- **UI:** SwiftUI with `MenuBarExtra` (macOS 14+)
- **iTerm2 Communication:** `NSAppleScript` (in-process, no subprocess spawning)
- **iTerm2 running check:** `NSRunningApplication` (instant, no AppleScript)
- **Build:** Swift Package Manager (`swift build`)

## File Structure

```
Sources/
├── SessionHubApp.swift              ← App entry point, MenuBarExtra
├── Models/
│   └── SessionStore.swift           ← @Observable state, polling, actions
├── Bridge/
│   └── iTerm2Bridge.swift           ← AppleScript communication with iTerm2
└── Views/
    └── MenuBarView.swift            ← Menu bar dropdown UI
```

## Key Design Decisions

1. **NSAppleScript over osascript subprocess** — Much faster. Running AppleScript in-process avoids process spawn overhead.
2. **NSRunningApplication for iTerm2 detection** — Instant check without AppleScript.
3. **Background queue for all bridge calls** — UI thread never blocks waiting for iTerm2.
4. **Sessions grouped by iTerm2 profile name** — Each profile = one project. User sets up profiles in iTerm2 Settings → Profiles with per-project working directories.
5. **§ delimiter in AppleScript output** — Avoids conflicts with pipe characters that might appear in session names.
6. **Polling interval of 2 seconds** — Balance between responsiveness and CPU usage.

## How to Build & Run

```bash
cd ~/Claude/SessionHub
swift build
.build/debug/SessionHub &
```

## How to Kill

```bash
pkill -f SessionHub
```

## Prerequisites

- iTerm2 installed with profiles configured per project
- macOS Automation permission (granted on first launch)
- Each iTerm2 profile should have:
  - A name matching the project (e.g., "FPL")
  - Initial directory set to the project folder (e.g., ~/Claude/FPL)
  - Optional: unique tab color for visual identification

## Roadmap / TODO

### Phase 3: Floating Panel (next priority)
- `NSPanel` with `.floating` window level
- Same project tree as menu bar but always visible
- Toggle on/off in settings
- Auto-show when iTerm2 is the frontmost app
- ~220px wide, remembers position

### Phase 4: Manager Window
- Standard `NSWindow` opened from menu bar
- Inline rename (double-click)
- Create/close sessions
- Drag to reorder

### Phase 5: Settings & Polish
- Polling interval adjustment (1s / 2s / 5s)
- Floating panel toggle
- Launch at login
- Keyboard shortcut for panel visibility
- App icon design
- Smooth animations
- Error handling (iTerm2 not running, permissions)
- First-launch onboarding

### Performance Ideas
- Consider iTerm2 Python API for event-driven updates (no polling)
- Cache profile list to avoid re-fetching

### Feature Ideas
- Search/filter sessions by name
- Show working directory per session
- Show git branch per session
- Session status indicators (idle vs. active)
- Keyboard shortcuts for switching (e.g., ⌘1-9)
