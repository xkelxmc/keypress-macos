# Key Visualization

## Visual Style

### Skeuomorphic 3D Keycaps

Keys should look like real mechanical keyboard keycaps:

- **Key well** — Dark recessed background the key sits in
- **Top surface** — Slightly concave with gradient (lighter at top)
- **Sides** — Visible depth between well and top surface
- **Shadow** — Soft blur beneath the entire key

The key is NOT a flat rectangle with text — it's a 3D object with volume.

### Keycap Structure

```
┌──────────────────────────┐  ← Key well (dark background)
│  ┌──────────────────┐    │
│  │                  │    │  ← Top surface (colored, with gradient)
│  │       ⌘         │    │
│  │    command       │    │  ← Label (icon + text for modifiers)
│  │                  │    │
│  └──────────────────┘    │
│         ▓▓▓▓▓▓           │  ← Visible depth/sides
└──────────────────────────┘
        ░░░░░░░░              ← Soft shadow
```

### Key Sizes

| Size | Width | Height | Usage |
|------|-------|--------|-------|
| Standard | 48pt | 48pt | Letters, digits, punctuation |
| Modifier | 72pt | 48pt | ⌘ ⌥ ⌃ ⇧ with icon + label |
| Wide | 80pt | 48pt | Space, Tab, Return, Delete |

## Press Animation

Keys can be in two visual states: **pressed** (physically held down) and **released** (visible but not held).

### Pressed State

When a key is physically pressed:

1. **Top surface shifts down** — 2.5pt for Mechanical, 1.5pt for Flat
2. **Sides compress** — Depth reduced by 2pt (Mechanical only)
3. **Shadow reduces** — Opacity × 0.5, blur radius decreases
4. **Minimal style** — Scales to 95%, opacity increases

### Released State

When key is released but still visible:

1. **Spring back** — Quick return to resting state (0.15s spring animation)
2. **Natural feel** — Spring with 0.7 damping fraction

### Animation Timing

- **Overlay appears** — Press animation delayed 0.2s (waits for fade-in)
- **Overlay already visible** — Press animation immediate (~20ms)
- **Transition** — Spring animation (response: 0.15s, damping: 0.7)

### Settings

Both modifier and regular key animations can be toggled independently in Style settings:
- **Modifier press animation** — For ⌘ ⌥ ⌃ ⇧
- **Key press animation** — For regular keys (letters, digits, etc.)

## Layout

### Pseudo-Keyboard Block

NOT a full keyboard layout. Just the pressed keys arranged inline:

```
┌─────┐ ┌─────┐ ┌─────┐
│  ⌘  │ │ ⇧  │ │  K  │
└─────┘ └─────┘ └─────┘
```

- Keys appear left-to-right in press order
- Modifiers typically shown first
- Small gap between keys
- Entire block has subtle background/border (keyboard fragment feel)

### Single Key

When pressing just one key, still show within the "fragment" context:

```
┌─────┐
│  A  │
└─────┘
```

## Key Labels

### Regular Keys
- Letters displayed uppercase (A, B, C...)
- Digits as-is (0-9)
- Single symbol centered on keycap

### Modifier Keys
Modifiers show **icon + label** stacked vertically:

```
┌────────────┐
│     ⇧      │  ← Icon (large)
│   shift    │  ← Label (small)
└────────────┘
```

| Modifier | Icon | Label |
|----------|------|-------|
| Command | ⌘ | command |
| Shift | ⇧ | shift |
| Option | ⌥ | option |
| Control | ⌃ | control |
| Fn | fn | (no label) |

> **Note:** Caps Lock is not supported — macOS doesn't provide reliable press/release events for it.

### Special Keys
- Escape: ESC
- Return: ⏎
- Tab: ⇥
- Delete/Backspace: ⌫
- Forward Delete: ⌦
- Space: ␣
- Arrows: ← → ↑ ↓
- Function keys: F1, F2, ... F20

### Keyboard Layout Support

- **Respects current keyboard layout** — typing in Russian shows Cyrillic, German shows umlauts, etc.
- Characters extracted from CGEvent at runtime, not hardcoded English
- Shift modifier affects displayed character (e.g., `!` instead of `1`)

## Timing

| State | Duration |
|-------|----------|
| Press animation | Spring 0.15s (response) |
| Release animation | Spring 0.15s with 0.7 damping |
| Modifier visible | While held, or with associated key |
| Regular key visible | Configurable timeout (default 1.5s) |
| Overlay fade in/out | 0.2s ease-out |
| Press animation delay on appear | 0.2s (matches fade-in) |

## Edge Cases

- **Rapid typing** — Keys queue and display, older ones fade faster
- **Repeated letters** — Each keypress creates unique entry (typing "hello" shows 5 keys: h e l l o)
- **Key repeat** — Show as held (no repeated animation)
- **Many keys at once** — Limit display to ~6 keys max, prioritize modifiers
