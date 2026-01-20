# Features

## Core Functionality

### Key Visualization

- Display pressed keys as realistic 3D mechanical keycaps
- Show all keys (letters, numbers, modifiers, special keys)
- Combinations displayed inline in a single block (e.g., ⌘ + Shift + K)
- No permanent window — visualization appears only when typing

### Key Behavior

| Key Type | Disappear Behavior |
|----------|-------------------|
| Modifiers (Cmd, Ctrl, Shift, Alt) | On key release |
| Regular keys | After configurable timeout |
| Held keys | Stay visually pressed while held |

### Positioning

- 8 preset positions: 4 corners + 4 edge centers
- Configurable edge offset (horizontal 0-500px, vertical 0-300px)
- Visual position picker in settings (mini monitor preview)
- Content aligns to the nearest edge based on selected position

## Menu Bar

### Tray Icon

- Persistent menu bar icon (no Dock icon)
- Click opens control menu

### Menu Contents

- App version
- Status indicator (active/inactive with green/red dot)
- Global hotkey hint
- Toggle button (enable/disable)
- Settings button
- Quit button

## Settings

Settings are organized into 5 tabs:

### General Tab
- Size (Small/Medium/Large)
- Opacity
- Key timeout
- Launch at login
- Global hotkey

### Position Tab
- Multi-monitor visualization with real wallpapers
- Auto mode (follows focused window) or fixed monitor
- 8 preset positions with visual indicators
- Per-monitor position and size controls

### Display Tab
- Display mode (Single/History)
- Mode-specific options

### Colors Tab
- Color scheme (Auto/Dark/Mono/Light/Custom)
- Key Style Editor (Custom mode) — master-detail UI for per-category customization

### Style Tab
- Keycap style (Mechanical/Flat/Minimal)
- Background style (Frame/Overlay/None)
- Press animation toggles (modifiers and regular keys)

## Window Behavior

- Always on top of all windows
- Click-through (mouse events pass through)
- Transparent background
- No window chrome (borderless)

## Future Considerations

- Statistics/analytics (typing speed, key frequency)
- Multiple visual themes
- Custom key filtering (show only shortcuts)
