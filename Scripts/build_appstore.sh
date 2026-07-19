#!/usr/bin/env bash
# Build and sign Keypress for Mac App Store submission via a generated Xcode
# project (xcodegen + xcodebuild archive/export). Xcode stamps all bundle
# metadata App Store processing expects — hand-rolled bundles get silently
# dropped server-side.
# Produces Keypress-<version>.pkg ready for upload to App Store Connect.
#
# Required env:
#   PROVISIONING_PROFILE    Path to the Mac App Store .provisionprofile
#   APP_IDENTITY            App signing identity name (Apple Distribution /
#                           3rd Party Mac Developer Application)
#   INSTALLER_IDENTITY      Installer signing identity name (Mac Installer
#                           Distribution / 3rd Party Mac Developer Installer)
# Requires both certificates in the keychain and xcodegen installed.

set -euo pipefail

APP_NAME="Keypress"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"

PKG_NAME="${APP_NAME}-${MARKETING_VERSION}.pkg"
XCCONFIG="Config/appstore-signing.xcconfig"

if [[ -z "${PROVISIONING_PROFILE:-}" || ! -f "${PROVISIONING_PROFILE:-}" ]]; then
  echo "ERROR: PROVISIONING_PROFILE must point to a .provisionprofile file" >&2
  exit 1
fi
for var in APP_IDENTITY INSTALLER_IDENTITY; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is required" >&2
    exit 1
  fi
done
command -v xcodegen >/dev/null || { echo "ERROR: xcodegen not installed (brew install xcodegen)" >&2; exit 1; }

WORK_DIR=$(mktemp -d)
cp "$XCCONFIG" "$WORK_DIR/xcconfig.default"
trap 'cp "$WORK_DIR/xcconfig.default" "$XCCONFIG"; rm -rf "$WORK_DIR"' EXIT

echo "==> Reading provisioning profile"
security cms -D -i "$PROVISIONING_PROFILE" > "$WORK_DIR/profile.plist"
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$WORK_DIR/profile.plist")
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :Name' "$WORK_DIR/profile.plist")
TEAM_ID=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$WORK_DIR/profile.plist")
echo "    profile: $PROFILE_NAME ($PROFILE_UUID), team: $TEAM_ID"

PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"
cp "$PROVISIONING_PROFILE" "$PROFILE_DIR/$PROFILE_UUID.provisionprofile"

cat > "$XCCONFIG" <<EOF
CODE_SIGN_STYLE = Manual
DEVELOPMENT_TEAM = ${TEAM_ID}
CODE_SIGN_IDENTITY = ${APP_IDENTITY}
PROVISIONING_PROFILE_SPECIFIER = ${PROFILE_NAME}
EOF

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Archiving"
ARCHIVE="build/${APP_NAME}.xcarchive"
rm -rf build
xcodebuild archive -quiet \
  -project "${APP_NAME}.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -archivePath "$ARCHIVE" -destination 'generic/platform=macOS' \
  MARKETING_VERSION="$MARKETING_VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

APP_IN_ARCHIVE="$ARCHIVE/Products/Applications/${APP_NAME}.app"
lipo -info "$APP_IN_ARCHIVE/Contents/MacOS/$APP_NAME"
codesign -d --entitlements :- "$APP_IN_ARCHIVE" 2>/dev/null | grep -q "com.apple.application-identifier" || {
  echo "ERROR: archived app is missing com.apple.application-identifier" >&2
  exit 1
}

echo "==> Exporting .pkg for App Store Connect"
cat > "$WORK_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>export</string>
    <key>signingStyle</key><string>manual</string>
    <key>teamID</key><string>${TEAM_ID}</string>
    <key>signingCertificate</key><string>${APP_IDENTITY}</string>
    <key>installerSigningCertificate</key><string>${INSTALLER_IDENTITY}</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>dev.keypress.app</key><string>${PROFILE_NAME}</string>
    </dict>
</dict>
</plist>
EOF
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$WORK_DIR/ExportOptions.plist" \
  -exportPath build/export

rm -f "$PKG_NAME"
mv "build/export/${APP_NAME}.pkg" "$PKG_NAME"
pkgutil --check-signature "$PKG_NAME"

echo "Done: $PKG_NAME"
