#!/usr/bin/env bash
# Build Icon.icns from a source PNG (1024x1024 recommended).
# Usage: ./Scripts/build_icon.sh [source.png]

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE=${1:-"$ROOT/icon_source.png"}
OUTPUT="$ROOT/Icon.icns"
ICONSET_DIR="$ROOT/Icon.iconset"

if [[ ! -f "$SOURCE" ]]; then
  echo "Source image not found: $SOURCE"
  echo "Usage: $0 <source.png>  (1024x1024 PNG recommended)"
  exit 1
fi

# Create iconset directory
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Generate all required sizes
sizes=(16 32 64 128 256 512)
for sz in "${sizes[@]}"; do
  sips -z "$sz" "$sz" "$SOURCE" --out "$ICONSET_DIR/icon_${sz}x${sz}.png" >/dev/null
  dbl=$((sz * 2))
  sips -z "$dbl" "$dbl" "$SOURCE" --out "$ICONSET_DIR/icon_${sz}x${sz}@2x.png" >/dev/null
done

# 512@2x is 1024
sips -z 1024 1024 "$SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

# Convert iconset to icns
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT"

# Cleanup
rm -rf "$ICONSET_DIR"

echo "Created $OUTPUT"
