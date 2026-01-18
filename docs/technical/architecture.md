# Architecture

## Modules

```
Sources/
├── KeypressCore/       # Core logic, no UI dependencies
│   ├── KeyMonitor      # CGEvent tap, key event processing
│   ├── KeyState        # Current pressed keys state
│   └── Settings        # Settings storage and defaults
│
├── Keypress/           # Main app target
│   ├── App             # Entry point, AppDelegate
│   ├── MenuBar         # Status item, dropdown menu
│   ├── Overlay         # Key visualization window
│   ├── Views           # SwiftUI views (keys, settings)
│   └── Settings        # Settings window
│
└── KeypressTests/      # Unit tests
```

## Data Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  KeyMonitor  │────▶│   KeyState   │────▶│   Overlay    │
│  (CGEvent)   │     │  (pressed)   │     │   (SwiftUI)  │
└──────────────┘     └──────────────┘     └──────────────┘
                            │
                            ▼
                     ┌──────────────┐
                     │   Settings   │
                     │ (UserDefaults)│
                     └──────────────┘
```

1. **KeyMonitor** captures global keyboard events via CGEvent tap
2. **KeyState** maintains set of currently pressed keys
3. **Overlay** subscribes to KeyState and renders visualization
4. **Settings** provides configuration (timeout, position, etc.)

## Entry Points

- `KeypressApp` — SwiftUI App, Settings scene
- `AppDelegate` — Menu bar setup, event tap initialization

## Concurrency

- Key events arrive on background queue
- UI updates dispatched to `@MainActor`
- Use `@Observable` (Swift 5.9+) for reactive state

## Key Components

### KeyMonitor

- Creates `CGEvent` tap for keyboard events
- Filters relevant events (keyDown, keyUp, flagsChanged)
- Translates keycodes to displayable symbols
- Publishes to KeyState

### KeyState

- `@Observable` class
- Tracks currently pressed keys with timestamps
- Handles modifier vs regular key logic
- Triggers fade-out timers

### OverlayWindow

- Custom `NSPanel` subclass
- Hosts SwiftUI `KeyVisualizationView`
- Manages positioning based on settings
- Handles show/hide animations

### MenuBarController

- Creates `NSStatusItem`
- Builds `NSMenu` with status, controls
- Handles toggle, settings, quit actions
