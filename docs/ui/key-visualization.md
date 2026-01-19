# Key Visualization

## Visual Style

### Skeuomorphic 3D Keycaps

Keys should look like real mechanical keyboard keycaps:

- **Top surface** — Slightly concave, lighter color
- **Sides** — Visible depth, darker shade
- **Base** — Shadow beneath the key

The key is NOT a flat rectangle with text — it's a 3D object with volume.

## Press Animation

When a key is pressed:

1. **Top surface shifts down** — The main visual cue of pressing
2. **Sides compress** — Less visible side surface
3. **Shadow reduces** — Key is closer to the surface
4. **Optional: subtle glow** — Highlight on press

When released:

1. **Spring back** — Quick return to resting state
2. **Subtle bounce** — Natural mechanical feel

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

- Use SF Symbols for special keys where appropriate
- Standard symbols: ⌘ ⌥ ⌃ ⇧ ⎋ ⏎ ⌫ ⇥
- Letters displayed uppercase
- Function keys: F1, F2, etc.

### Keyboard Layout Support

- **Respects current keyboard layout** — typing in Russian shows Cyrillic, German shows umlauts, etc.
- Characters extracted from CGEvent at runtime, not hardcoded English
- Shift modifier affects displayed character (e.g., `!` instead of `1`)

## Timing

| State | Duration |
|-------|----------|
| Press animation | ~50ms |
| Release animation | ~100ms (with slight bounce) |
| Modifier visible | While held |
| Regular key visible | Configurable timeout (default ~1.5s) |
| Fade out | ~200ms ease-out |

## Edge Cases

- **Rapid typing** — Keys queue and display, older ones fade faster
- **Repeated letters** — Each keypress creates unique entry (typing "hello" shows 5 keys: h e l l o)
- **Key repeat** — Show as held (no repeated animation)
- **Many keys at once** — Limit display to ~6 keys max, prioritize modifiers
