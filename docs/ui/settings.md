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

### Appearance

| Setting | Control Type | Default |
|---------|-------------|---------|
| Size | Slider (Small → Large) | Medium |
| Opacity | Slider (0% → 100%) | 100% |

### Behavior

| Setting | Control Type | Default |
|---------|-------------|---------|
| Key timeout | Slider (0.5s → 5s) | 1.5s |
| Global hotkey | Hotkey recorder | ⌘⇧K |

## Persistence

- Settings stored in UserDefaults
- Sync across app launches
- Consider CloudKit sync for multiple Macs (v2)
