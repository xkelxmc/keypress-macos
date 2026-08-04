# App Icon

The 2.0.0 brand icon: the Keypress cat peeking over a dark graphite mechanical
keycap with a cyan backlit "K", on a moody near-black tile. A runner-up
variant (⌘K legends, no cat) is kept alongside the primary art.

## Source Files

- `assets/icon/icon-art-cat.png` — primary full-bleed artwork (AI-generated,
  gpt-image-2, 1254x1254)
- `assets/icon/icon-art-cmdk.png` — runner-up artwork (⌘K, no cat)
- `icon_source.png` — masked 1024x1024 icon (generated, Big Sur template:
  824x824 rounded tile + shadow on transparent canvas)
- `Icon.icns` — macOS icon bundle (generated)
- `icon_source.svg` — legacy 1.x vector source, superseded by the artwork above

## Updating the Icon

1. Replace or regenerate the artwork in `assets/icon/` (full-bleed square,
   1024+ px; keep the subject inside ~9% margins so the squircle mask never
   clips it).
2. Mask and rebuild:

```bash
swift Scripts/mask_icon.swift assets/icon/icon-art-cat.png icon_source.png
./Scripts/build_icon.sh
```

3. Rebuild the app to see changes:

```bash
bun run start
```

## Requirements

- `swift` (mask script uses AppKit), `sips` and `iconutil` — all built into
  macOS / Xcode tooling.

## Design guidelines

- Full-bleed artwork is masked into the standard Big Sur tile (824x824,
  corner radius 185.4, soft drop shadow). macOS 26 re-masks icons with its own
  squircle; older versions show the tile as-is, so both look correct.
- Palette matches the marketing "Neon Stage": near-black graphite, restrained
  indigo/cyan glow, cyan backlit legend, amber-eyed sticker cat (the in-app
  pet).
