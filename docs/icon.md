# App Icon

The app icon shows a mechanical keycap with "⌘ K" text on a dark circular background.

## Source Files

- `icon_source.svg` — Vector source (edit this)
- `icon_source.png` — Rasterized PNG (1024×1024)
- `Icon.icns` — macOS icon bundle (generated)

## Updating the Icon

1. Edit `icon_source.svg` in the project root
2. Convert to PNG and build ICNS:

```bash
# Convert SVG to PNG
rsvg-convert -w 1024 -h 1024 icon_source.svg -o icon_source.png

# Build ICNS from PNG
./Scripts/build_icon.sh
```

Or in one command:

```bash
rsvg-convert -w 1024 -h 1024 icon_source.svg -o icon_source.png && ./Scripts/build_icon.sh
```

3. Rebuild the app to see changes:

```bash
bun run start
```

## Requirements

- `rsvg-convert` for SVG→PNG conversion (install via `brew install librsvg`)
- `sips` and `iconutil` for ICNS generation (built into macOS)

## Icon Design Guidelines

- 1024×1024 canvas with 480px radius circle background
- Dark theme (#1a1a1a background)
- 3D keycap effect with layered rectangles
- SF Pro Display or system font for text
