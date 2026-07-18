#!/usr/bin/env bash
# Package Keypress.app bundle from Swift build output.

set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Load version info
source "$ROOT/version.env"

APP_NAME="Keypress"
BUNDLE_ID="dev.keypress.app"
VERSION="${MARKETING_VERSION}"

# Build (set ARCHES="arm64 x86_64" for a universal binary).
# Each arch is built separately and merged with lipo: the combined
# multi-arch swift build is flaky across Xcode versions.
ARCHES=${ARCHES:-$(uname -m)}
BINARIES=()
BUILD_DIR=""
for ARCH in $ARCHES; do
  swift build -c "$CONF" --arch "$ARCH"
  ARCH_DIR=".build/${ARCH}-apple-macosx/$CONF"
  [[ -f "$ARCH_DIR/$APP_NAME" ]] || ARCH_DIR=".build/$CONF"
  BINARIES+=("$ARCH_DIR/$APP_NAME")
  [[ -n "$BUILD_DIR" ]] || BUILD_DIR="$ARCH_DIR"
done

# Create app bundle structure
APP="$ROOT/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Info.plist
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>NSHumanReadableCopyright</key><string>© 2025 Ilya Zhidkov. MIT License.</string>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>ITSAppUsesNonExemptEncryption</key><false/>
</dict>
</plist>
PLIST

# Copy binary (lipo merges when multiple arches were built)
if [[ ${#BINARIES[@]} -gt 1 ]]; then
  lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
else
  cp "${BINARIES[0]}" "$APP/Contents/MacOS/$APP_NAME"
fi
chmod +x "$APP/Contents/MacOS/$APP_NAME"

# Copy icon if exists
if [[ -f "$ROOT/Icon.icns" ]]; then
  cp "$ROOT/Icon.icns" "$APP/Contents/Resources/Icon.icns"
fi

# Copy SwiftPM resource bundles (e.g., KeyboardShortcuts)
shopt -s nullglob
for bundle in "$BUILD_DIR"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
shopt -u nullglob

# Strip extended attributes
xattr -cr "$APP" 2>/dev/null || true

# Ad-hoc sign
codesign --force --sign - "$APP"

echo "Created $APP"
