# Architecture

## Modules

```
Sources/
├── KeypressCore/
│   ├── KeyMonitor         # Existing listen-only keyboard CGEvent tap
│   ├── KeyState           # Single and horizontal keyboard state
│   ├── StackedHistory     # Grouped in-memory history
│   └── KeypressConfig     # Versioned settings and migration
│
├── Keypress/
│   ├── AppDelegate        # Menu bar and global actions
│   ├── Overlay            # Pointer tap plus keyboard, cursor, and HUD windows
│   ├── Views              # Keycap and overlay rendering
│   ├── Settings           # Native Studio settings window
│   └── ScreenshotGenerator
│
└── Tests/
```

## Input Flow

`KeyMonitor` keeps the proven keyboard-only listen-only `CGEventTap` on its
dedicated thread. `PointerInputMonitor` owns a separate listen-only tap, copies
only pointer event primitives, and immediately returns the original event.
Neither tap performs UI work.

Keyboard events feed one of three in-memory state models:

- `SingleKeyState`
- `KeyState` for Horizontal History
- `StackedHistoryState`

Pointer events feed `PointerOverlayController`, which resolves the latest
physical cursor location and recovers missed button releases. No input history
is written to disk.

## Presentation

`OverlayController` coordinates:

- one keyboard window for Follow Pointer or One Display;
- one keyboard window per connected target in Selected Displays;
- one cursor halo window on the physical pointer display;
- one independent HUD window;
- one temporary full-screen placement editor.

All production overlay windows are transparent, non-activating, click-through
panels that join every Space. The placement editor is the only interactive
overlay.

## Settings

`KeypressConfig` is a main-actor observable facade over one versioned
`AppSettings` snapshot. The snapshot groups general, keyboard, pointer,
appearance, display, and HUD settings. Legacy individual `UserDefaults` keys
are read once and migrated without deleting the old values.

In-memory settings change immediately. Disk persistence is coalesced during
continuous edits and explicitly flushed when the application terminates.

Display preferences use stable `CGDisplay` UUID strings. Custom placement stores
a normalized visual center inside `NSScreen.visibleFrame`, keeping the result
stable across scaling, resolution, menu bar, and Dock changes.

## Permissions and Concurrency

- Input Monitoring is the only requested privacy permission.
- Accessibility and Screen Recording are not required.
- UI and settings state are isolated to `@MainActor`.
- The event tap lifecycle is protected against start/stop races.
- Secure Input clears and suppresses keyboard presentation while pointer
  visualization remains available.
