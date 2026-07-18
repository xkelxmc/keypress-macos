# Technical Overview

## Tech Stack

- **Language**: Swift 6 with strict concurrency
- **UI Framework**: SwiftUI + AppKit (for menu bar, overlay window)
- **Build System**: Swift Package Manager
- **Minimum macOS**: 14+ (Sonoma)

## Key Dependencies

- **KeyboardShortcuts** — Global hotkey registration

## macOS APIs

### Input Monitoring

- `CGEvent` tap (listen-only) for global keyboard events
- Requires the Input Monitoring permission (sandbox-compatible, via `IOHIDRequestAccess`)

### Overlay Window

- `NSPanel` with specific flags:
  - `.nonactivatingPanel` — Doesn't steal focus
  - `collectionBehavior: .canJoinAllSpaces` — Visible on all desktops
  - `isOpaque: false` — Transparent background
  - `ignoresMouseEvents: true` — Click-through

### Menu Bar

- `NSStatusItem` for tray icon
- `NSMenu` for dropdown menu
- No `NSApplication.setActivationPolicy(.accessory)` — No Dock icon

## Permissions

| Permission | Why Needed |
|------------|------------|
| Input Monitoring | Capture global keyboard events |

## Project Structure

See [Architecture](./architecture.md) for module breakdown.
