# Screenshots

## Structure

```
assets/screenshots/
├── README.md                  # This file
├── screenshot-bg-light.png    # Light wallpaper background
├── screenshot-bg-dark.png     # Dark wallpaper background
└── generated/                 # Generated screenshots (gitignored)
    └── keypress-*_*.png
```

## Generate screenshots

### 1. Prepare background images

Extract frames from macOS wallpaper videos (Tahoe example):

```bash
cd ~/Library/Containers/com.apple.NeptuneOneExtension/Data/Library/Application\ Support/Videos/
ffmpeg -i "Tahoe Light Landscape.mov" -vframes 1 assets/screenshots/screenshot-bg-light.png
ffmpeg -i "Tahoe Dark Landscape.mov" -vframes 1 assets/screenshots/screenshot-bg-dark.png
```

Or use any 16:9 images as backgrounds.

### 2. Build and run

```bash
swift build
.build/debug/Keypress --screenshot both
```

Options:
- `light` — Generate only light mode
- `dark` — Generate only dark mode
- `both` — Generate both (default)

Screenshots saved to `generated/` with timestamps.

### 3. Copy to assets/images for README

```bash
cp assets/screenshots/generated/keypress-light_*.png assets/images/preview-light.png
cp assets/screenshots/generated/keypress-dark_*.png assets/images/preview-dark.png
```
