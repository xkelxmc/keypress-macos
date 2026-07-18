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

echo "==> Signing with $APP_IDENTITY"
codesign --force --timestamp --sign "$APP_IDENTITY" \
  --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

codesign --verify --deep --strict "$APP_BUNDLE"
codesign -d --entitlements - "$APP_BUNDLE"

echo "==> Building installer package"
rm -f "$PKG_NAME"
productbuild --component "$APP_BUNDLE" /Applications \
  --sign "$INSTALLER_IDENTITY" "$PKG_NAME"

echo "Done: $PKG_NAME"
