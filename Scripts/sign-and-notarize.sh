#!/usr/bin/env bash
# Sign and notarize Keypress.app for distribution.
# Requires:
#   - APP_IDENTITY: Developer ID Application certificate name
#   - APP_STORE_CONNECT_API_KEY_P8: API key content
#   - APP_STORE_CONNECT_KEY_ID: API key ID
#   - APP_STORE_CONNECT_ISSUER_ID: Issuer ID

set -euo pipefail

APP_NAME="Keypress"
APP_BUNDLE="Keypress.app"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/version.env"

ZIP_NAME="${APP_NAME}-${MARKETING_VERSION}.zip"

# Validate required env vars
if [[ -z "${APP_IDENTITY:-}" ]]; then
  echo "APP_IDENTITY is required (e.g., 'Developer ID Application: Your Name (TEAMID)')" >&2
  exit 1
fi

if [[ -z "${APP_STORE_CONNECT_API_KEY_P8:-}" || -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo "Missing APP_STORE_CONNECT_* env vars (API key, key id, issuer id)." >&2
  exit 1
fi

# Build release
ARCHES=${ARCHES:-"arm64 x86_64"}
for ARCH in $ARCHES; do
  swift build -c release --arch "$ARCH"
done
ARCHES="$ARCHES" ./Scripts/package_app.sh release

# Write API key to temp file
echo "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > /tmp/keypress-api-key.p8
trap 'rm -f /tmp/keypress-api-key.p8 /tmp/${APP_NAME}Notarize.zip' EXIT

# Sign the app
echo "Signing with $APP_IDENTITY"
codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" "$APP_BUNDLE"

# Create zip for notarization
ditto -c -k --keepParent "$APP_BUNDLE" "/tmp/${APP_NAME}Notarize.zip"

# Submit for notarization
echo "Submitting for notarization..."
xcrun notarytool submit "/tmp/${APP_NAME}Notarize.zip" \
  --key /tmp/keypress-api-key.p8 \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

# Staple the ticket
echo "Stapling ticket..."
xcrun stapler staple "$APP_BUNDLE"

# Clean up extended attributes
xattr -cr "$APP_BUNDLE"

# Create final distribution zip
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_NAME"

# Verify
spctl -a -t exec -vv "$APP_BUNDLE"
stapler validate "$APP_BUNDLE"

echo "Done: $ZIP_NAME"
