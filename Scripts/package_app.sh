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

# Build (set ARCHES="arm64 x86_64" for a universal binary)
ARCHES=${ARCHES:-$(uname -m)}
ARCH_FLAGS=()
for ARCH in $ARCHES; do
  ARCH_FLAGS+=(--arch "$ARCH")
done
swift build -c "$CONF" "${ARCH_FLAGS[@]}"

# SwiftPM output: single-arch in .build/<arch>-apple-macosx/<conf>, multi-arch in .build/apple/Products/<Conf>
if [[ $(echo "$ARCHES" | wc -w) -gt 1 ]]; then
  CONF_TITLE=$(echo "${CONF:0:1}" | tr '[:lower:]' '[:upper:]')${CONF:1}
  BUILD_DIR=".build/apple/Products/${CONF_TITLE}"
else
  BUILD_DIR=".build/${ARCHES// /}-apple-macosx/$CONF"
  [[ -f "$BUILD_DIR/$APP_NAME" ]] || BUILD_DIR=".build/$CONF"
fi

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
    <key>SUFeedURL</key><string>https://raw.githubusercontent.com/xkelxmc/keypress-macos/main/appcast.xml</string>
    <key>SUPublicEDKey</key><string>vGdL7QPuGcShL2RpiohpJe9YK/oV5hx3S3LEMU2Lb8c=</string>
    <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
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

# Embed Sparkle.framework
if [[ -d "$BUILD_DIR/Sparkle.framework" ]]; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "$BUILD_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
  chmod -R a+rX "$APP/Contents/Frameworks/Sparkle.framework"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME"

  # Re-sign Sparkle components (ad-hoc)
  SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --sign - "$SPARKLE/Versions/B/Sparkle"
  codesign --force --sign - "$SPARKLE/Versions/B/Autoupdate"
  codesign --force --sign - "$SPARKLE/Versions/B/Updater.app"
  codesign --force --sign - "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --sign - "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
  codesign --force --sign - "$SPARKLE"
fi

# Strip extended attributes
xattr -cr "$APP" 2>/dev/null || true

# Ad-hoc sign
codesign --force --sign - "$APP"

echo "Created $APP"
