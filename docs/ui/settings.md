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

- `Max keys` — maximum keys displayed at once
- `Duplicate letters` — when On, "hello" shows 5 keys; when Off, shows 4 (no repeat)

### Appearance

| Setting | Control Type | Default |
|---------|-------------|---------|
| Size | Slider (Small → Large) | Medium |
| Opacity | Slider (0% → 100%) | 100% |

### Key Colors

Different key types have distinct colors for better visual distinction.

| Key Category | Examples | Default Color |
|--------------|----------|---------------|
| Letters & Digits | A-Z, 0-9 | Gray (neutral) |
| Command ⌘ | Left/Right Command | Blue |
| Shift ⇧ | Left/Right Shift | Orange |
| Option ⌥ | Left/Right Option | Purple |
| Control ⌃ | Left/Right Control | Pink |
| Special keys | ⏎ ⇥ ␣ ⌫ ← → ↑ ↓ | Green |
| Escape ⎋ | Escape | Teal |
| Function keys | F1-F20 | Cyan |

#### Color customization

Each category can be customized:

| Setting | Control Type | Options |
|---------|-------------|---------|
| Color scheme | Picker | Default, Monochrome, Custom |
| [Category] color | Color picker | Per-category override |

**Presets:**
- **Default** — distinct colors per category (as above)
- **Monochrome** — all keys same color (gray/white)
- **Custom** — user picks each category color

### Behavior

| Setting | Control Type | Default |
|---------|-------------|---------|
| Key timeout | Slider (0.5s → 5s) | 1.5s |
| Global hotkey | Hotkey recorder | ⌘⇧K |

## Persistence

- Settings stored in UserDefaults
- Sync across app launches
- Consider CloudKit sync for multiple Macs (v2)
