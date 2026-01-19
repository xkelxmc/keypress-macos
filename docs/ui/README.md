# UI Overview

## Design Principles

1. **Invisible by default** — No permanent UI, appears only when needed
2. **Skeuomorphic realism** — Keys look like actual mechanical keyboard keycaps
3. **Physics-based animation** — Real press feel, not just color changes
4. **Minimal chrome** — No window borders, transparent background

## UI Components

### Key Overlay

The main visualization that appears when typing. See [Key Visualization](./key-visualization.md).

- Floating pseudo-keyboard fragment (1-3 keys)
- Appears at configured screen position
- Fades out after inactivity

### Menu Bar

- Tray icon for app control
- Dropdown menu with status, toggle, settings access
- No Dock icon

### Settings Window

Native macOS settings window. See [Settings](./settings.md).

- Position picker with visual monitor preview
- Standard preferences controls

## Color Scheme

- Auto light/dark mode (follows system)
- Manual scheme selection (Dark, Monochrome, Light, Custom)
- Per-category color customization in Custom mode
- Key colors should work on any background
- Subtle shadows for depth perception
