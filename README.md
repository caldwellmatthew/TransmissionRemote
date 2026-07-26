# Transmission Remote

A native macOS client for a remote [Transmission](https://transmissionbt.com) daemon. SwiftUI, no dependencies.

## Features

- Sortable table with customizable columns — every RPC field is available, and layout and sort order persist
- Filter by status, search by name
- Add torrents from Finder, drag and drop, magnet links, or a pasted URL
- Start, pause, remove, verify, reannounce, reorder the queue, set priority, edit labels, change location
- Detail window (⌘I) with info, file tree, trackers, and peers
- Server speed limits, plus turtle mode with scheduled hours
- Port forwarding: set the peer port or randomize it on start, toggle UPnP/NAT-PMP, and test whether the port is open
- Menu bar extra with rates and a turtle toggle; notification when a download finishes

## Requirements

macOS 14 or later, Xcode with the Swift 6 toolchain, and a reachable Transmission daemon with RPC enabled.

## Build

```bash
xcodebuild -scheme TransmissionRemote build
xcodebuild -scheme TransmissionRemote test -destination 'platform=macOS'
```

Or open `TransmissionRemote.xcodeproj` in Xcode. Add `-configuration Release` for a build you intend to keep. Tests use [Swift Testing](https://developer.apple.com/documentation/testing) and cover the pure logic.

## Configuration

Settings (⌘,) → server address → **Connect**. A bare `host:port` works: the scheme defaults to `http`, and `/transmission/rpc` is appended when missing. Credentials are stored in the Keychain, everything else in `UserDefaults`. The refresh interval defaults to 5 seconds, minimum 1.

## Layout

```
TransmissionRemote/
  TransmissionRemoteApp.swift   Scenes, menu commands, Apple Event handling
  Model/                        Codable RPC types
  Services/                     RPC client, app state, Keychain
  Views/                        List, detail, settings, sheets
TransmissionRemoteTests/        Swift Testing suites
```
