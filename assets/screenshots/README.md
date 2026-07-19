# App Store screenshots

The screenshot generator renders the shipping SwiftUI keycap and keyboard frame components into seven deterministic
Mac App Store frames. Each PNG is exactly 2880×1800 pixels.

## Background images

The `hero`, `in-context`, and `unobtrusive` scenes require these files:

- `assets/screenshots/screenshot-bg-dark.png`
- `assets/screenshots/screenshot-bg-light.png`

Extract frames from macOS wallpaper videos or provide other desktop PNGs:

```bash
ffmpeg -i "$HOME/Library/Containers/com.apple.NeptuneOneExtension/Data/Library/Application Support/Videos/Tahoe Light Landscape.mov" \
  -vframes 1 assets/screenshots/screenshot-bg-light.png
ffmpeg -i "$HOME/Library/Containers/com.apple.NeptuneOneExtension/Data/Library/Application Support/Videos/Tahoe Dark Landscape.mov" \
  -vframes 1 assets/screenshots/screenshot-bg-dark.png
```

## Generate screenshots

Run every scene from the repository root:

```bash
bun run screenshots
```

Render selected scenes by passing one or more IDs directly to the executable:

```bash
swift build
.build/debug/Keypress --screenshot hero colors
```

List the available scenes:

```bash
.build/debug/Keypress --screenshot list
```

Scenes are rendered in this order:

1. `hero` — Every keystroke, on screen.
2. `in-context` — Your audience sees what you pressed.
3. `single-mode` — Just the shortcut.
4. `history-mode` — Or every letter, as you type.
5. `unobtrusive` — Invisible until you type.
6. `keycap-styles` — Three ways to look.
7. `colors` — Your colors. Ten key categories.

Output is written to `assets/appstore/generated/` as stable `NN-<scene-id>.png` filenames. Re-running the generator
overwrites the existing files.
