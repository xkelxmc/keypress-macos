#!/usr/bin/env bash
# Build and sign Keypress for Mac App Store submission.
# Produces Keypress-<version>.pkg ready for upload to App Store Connect.
#
# Required env:
#   APP_IDENTITY            Apple Distribution (or 3rd Party Mac Developer Application) identity
#   INSTALLER_IDENTITY      Mac Installer Distribution (3rd Party Mac Developer Installer) identity
#   PROVISIONING_PROFILE    Path to the Mac App Store .provisionprofile for the bundle id

set -euo pipefail

APP_NAME="Keypress"
APP_BUNDLE="Keypress.app"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"

PKG_NAME="${APP_NAME}-${MARKETING_VERSION}.pkg"
ENTITLEMENTS="$ROOT/Keypress.entitlements"

for var in APP_IDENTITY INSTALLER_IDENTITY PROVISIONING_PROFILE; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is required" >&2
    exit 1
  fi
done

if [[ ! -f "$PROVISIONING_PROFILE" ]]; then
  echo "ERROR: Provisioning profile not found: $PROVISIONING_PROFILE" >&2
  exit 1
fi

echo "==> Building universal binary"
ARCHES=${ARCHES:-"arm64 x86_64"} ./Scripts/package_app.sh release
lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> Embedding provisioning profile"
cp "$PROVISIONING_PROFILE" "$APP_BUNDLE/Contents/embedded.provisionprofile"

# App Store processing silently drops builds whose signature lacks the
# application-identifier / team-identifier entitlements (Xcode injects them
# from the profile automatically; a manual codesign must do the same).
echo "==> Generating signing entitlements from the provisioning profile"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
security cms -D -i "$PROVISIONING_PROFILE" > "$WORK_DIR/profile.plist"
APP_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$WORK_DIR/profile.plist")
TEAM_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$WORK_DIR/profile.plist")
echo "    application-identifier: $APP_IDENTIFIER"
echo "    team-identifier:        $TEAM_IDENTIFIER"

SIGN_ENTITLEMENTS="$WORK_DIR/entitlements.plist"
cp "$ENTITLEMENTS" "$SIGN_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_IDENTIFIER" "$SIGN_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_IDENTIFIER" "$SIGN_ENTITLEMENTS"
plutil -lint "$SIGN_ENTITLEMENTS"

echo "==> Signing with $APP_IDENTITY"
codesign --force --timestamp --sign "$APP_IDENTITY" \
  --entitlements "$SIGN_ENTITLEMENTS" "$APP_BUNDLE"

codesign --verify --deep --strict "$APP_BUNDLE"
codesign -d --entitlements - "$APP_BUNDLE"
codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null | grep -q "com.apple.application-identifier" || {
  echo "ERROR: signed app is missing com.apple.application-identifier" >&2
  exit 1
}

echo "==> Building installer package"
rm -f "$PKG_NAME"
productbuild --component "$APP_BUNDLE" /Applications \
  --sign "$INSTALLER_IDENTITY" "$PKG_NAME"

echo "Done: $PKG_NAME"
