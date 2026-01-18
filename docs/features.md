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
- Visual position picker in settings (mini monitor preview)
- Possible drag-and-drop for custom positioning (v2)

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

## Settings (v1)

| Setting | Description |
|---------|-------------|
| Position | Where on screen to show keys |
| Size | Scale of the key visualization |
| Enabled | Master on/off toggle |
| Timeout | How long regular keys stay visible |
| Opacity | Transparency of the overlay |
| Launch at login | Auto-start with macOS |
| Global hotkey | Keyboard shortcut to toggle visibility |

## Window Behavior

- Always on top of all windows
- Click-through (mouse events pass through)
- Transparent background
- No window chrome (borderless)

## Future Considerations

- Statistics/analytics (typing speed, key frequency)
- Multiple visual themes
- Mouse click visualization
- Custom key filtering (show only shortcuts)
