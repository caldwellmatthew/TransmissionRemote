# CLAUDE.md

## Project
macOS Transmission remote client built with SwiftUI. Manages torrents on a remote Transmission server via its RPC API.

## Build
```bash
xcodebuild -scheme TransmissionRemote -configuration Debug build
```

## Architecture
- **TransmissionClient** (`actor`) — RPC transport layer. Caches session ID to avoid 409s. All server communication goes through here.
- **TorrentManager** (`@Observable @MainActor`) — App state. Polls every 5s. Injected via `.environment()`.
- **Torrent model** — `listFields` for table polling, `detailFields` for detail window (includes files, trackers, peers).

## Key patterns
- `Table` with `columnCustomization` and `@AppStorage` for persisted column state
- `WindowGroup(for: Int.self)` for per-torrent detail windows (opened via double-click or Cmd+I)
- `NotificationCenter` bridges menu commands to SwiftUI views
- Finder file opens and magnet links queue on `AppDelegate.pendingAdds` (observable, in the environment), not notifications — a launch-triggering event arrives before any view can observe it

## SwiftUI quirks encountered
- `ProgressView` causes rendering glitches during Table column reorder — use capsule + `scaleEffect` instead
- Table column builder has 10-column limit — wrap extras in `Group`
- `.toolbar(removing: .title)` requires macOS 15 — use `.navigationTitle("")` instead
- Pin the Name column with `.customizationID("name")` + `.disabledCustomizationBehavior(.all)` — omitting the ID makes SwiftUI park it at the end whenever stored customization re-applies
- Never swap a `Table` in and out with `if`/`switch` for state changes that recur (connection errors, empty lists) — keep it mounted and overlay the other state with `.opacity` + `.overlay`. Each teardown of its scroll view leaks AppKit's scroll-edge pocket views, along with their display-cycle and notification observers, and they accumulate for the life of the process
- Table empty placeholder rows don't fill width if total column ideal widths are too small — use large `ideal:` on flexible columns
