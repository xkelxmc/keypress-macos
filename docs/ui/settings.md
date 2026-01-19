# Settings Window

## Overview

Native macOS Settings window accessible from menu bar icon.

## Position Picker

Visual selector showing a mini monitor with 8 clickable regions:

```
┌─────────────────────────┐
│  ●       ●       ●     │
│                         │
│  ●               ●     │
│                         │
│  ●       ●       ●     │
└─────────────────────────┘
```

- 4 corners
- 4 edge centers (top, bottom, left, right)
- Active position highlighted
- Click to select
- Optional: drag indicator for custom position (v2)

## Settings Controls

### General

| Setting | Control Type | Default |
|---------|-------------|---------|
| Enabled | Toggle | On |
| Launch at login | Toggle | Off |
| Position | Visual picker | Bottom-right |
| Monitor | Picker | Auto |

#### Monitor Selection (v2)

Only shown when multiple monitors connected. Hidden for single monitor setups.

| Option | Behavior |
|--------|----------|
| **Auto** (default) | Follow focused window — overlay appears on the monitor where user is typing |
| **Monitor 1, 2, ...** | Fixed to specific monitor |

**Auto mode details:**
- Detects focused window's screen using Accessibility API (`kAXFocusedWindowAttribute`)
- Updates position on each keypress to catch window switches within the same app
- Example: 2 Chrome windows on different monitors — overlay follows the active Chrome window

### Display Mode

| Setting | Control Type | Default |
|---------|-------------|---------|
| Display mode | Picker (Single / History) | Single |

Two fundamentally different visualization approaches:

| Mode | Description | Best for |
|------|-------------|----------|
| **Single** | Only latest keystroke/combination visible. Each new key replaces previous. (Keystroke Pro 2 style) | Shortcut demos, teaching |
| **History** | Queue of recent keystrokes. Keys accumulate and fade over time. | Typing demos, streaming |

#### Mode-specific settings

**Single mode:**

| Setting | Control Type | Default |
|---------|-------------|---------|
| Show modifiers only | Toggle | Off |

When enabled, only shows combinations with modifiers (⌘, ⌥, ⌃, ⇧). Regular letters/numbers are hidden.

**History mode:**

| Setting | Control Type | Default |
|---------|-------------|---------|
| Max keys | Slider (3 → 12) | 6 |
| Duplicate letters | Toggle | On |
| Limit includes modifiers | Toggle | On |

- `Max keys` — maximum keys displayed at once
- `Duplicate letters` — when On, "hello" shows 5 keys; when Off, shows 4 (no repeat)
- `Limit includes modifiers` — when On, max keys applies to all keys; when Off, modifiers don't count towards the limit

### Appearance

| Setting | Control Type | Default |
|---------|-------------|---------|
| Size | Slider (Small → Large) | Medium |
| Opacity | Slider (0% → 100%) | 100% |

### Keycap Style

| Setting | Control Type | Default |
|---------|-------------|---------|
| Style | Picker | Mechanical |

**Styles:**
- **Mechanical** — 3D skeuomorphic keycaps with depth, shadows, and beveled edges
- **Flat** — Modern flat design with subtle shadows (future)
- **Minimal** — Text only with background (future)

### Key Colors

Different key types have distinct colors for better visual distinction.

| Key Category | Examples | Default Color (Dark) |
|--------------|----------|----------------------|
| Letters & Digits | A-Z, 0-9 | Charcoal `#262628` |
| Command ⌘ | Left/Right Command | Green `#33B373` |
| Shift ⇧ | Left/Right Shift | Red `#E64D40` |
| Option ⌥ | Left/Right Option | Blue `#4073F2` |
| Control ⌃ | Left/Right Control | Orange `#F28C33` |
| Caps Lock ⇪ | Caps Lock | Dark Gray `#595961` |
| Escape ⎋ | Escape | Teal `#33BFB3` |
| Function keys | F1-F20 | Purple `#9966CC` |
| Navigation | ← → ↑ ↓ Home End PgUp PgDn | Charcoal `#262628` |
| Editing | ⏎ ⇥ ␣ ⌫ ⌦ | Charcoal `#262628` |

#### Color Schemes

| Setting | Control Type | Options |
|---------|-------------|---------|
| Color scheme | Picker | Auto, Dark, Monochrome, Light, Custom |

**Built-in presets:**
- **Auto** (default) — follows system light/dark mode
- **Dark** — colored modifiers on charcoal base
- **Monochrome** — all keys charcoal
- **Light** — colored modifiers on aluminum base

**Custom scheme:**

When Custom mode is selected, a full Key Style Editor appears with master-detail UI:

```
┌─────────────────┬──────────────────────────────┐
│ Categories      │  Command ⌘              [on] │
│                 │                              │
│ ⌘ Command   [✓] │  Color     [████] [picker]   │
│ ⇧ Shift     [ ] │  Depth     [────●────]       │
│ ⌥ Option    [ ] │  Corners   [────●────]       │
│ ⌃ Control   [ ] │  Shadow    [────●────]       │
│ A Letters   [✓] │  Style     [Mechanical ▼]    │
│ → Navigation[ ] │                              │
│ ...             │                              │
└─────────────────┴──────────────────────────────┘
```

- **Sidebar** — list of 10 key categories with checkboxes
- **Checkbox** — enables custom style override for that category
- **Detail panel** — style settings for selected category

**Per-category style properties:**

| Property | Range | Description |
|----------|-------|-------------|
| Color | Color picker | Base color for the keycap |
| Depth | 0-100% | 3D depth effect intensity |
| Corners | 0-100% | Corner radius (sharp to rounded) |
| Shadow | 0-100% | Shadow intensity |
| Style | Picker | Keycap visual style |

Only customized categories are stored; others use defaults from the active color scheme.

### Behavior

| Setting | Control Type | Default |
|---------|-------------|---------|
| Key timeout | Slider (0.5s → 5s) | 1.5s |

### Shortcuts

| Setting | Control Type | Default |
|---------|-------------|---------|
| Toggle overlay | Hotkey recorder | None |

Global keyboard shortcut to toggle overlay on/off. Uses [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) library.

- Recorder allows user to set any key combination
- Shortcut hint shown in menu bar next to "Enabled" item
- Works globally, even when app is in background

## Persistence

- Settings stored in UserDefaults
- Sync across app launches
- Consider CloudKit sync for multiple Macs (v2)
