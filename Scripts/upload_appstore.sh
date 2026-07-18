#!/usr/bin/env bash
# Upload a signed .pkg to App Store Connect via altool.
# Usage: ./Scripts/upload_appstore.sh Keypress-<version>.pkg
#
# Required env:
#   APP_STORE_CONNECT_API_KEY_P8  App Store Connect API key content (.p8)
#   APP_STORE_CONNECT_KEY_ID      API key ID
#   APP_STORE_CONNECT_ISSUER_ID   Issuer ID

set -euo pipefail

PKG=${1:?"usage: $0 <package.pkg>"}

for var in APP_STORE_CONNECT_API_KEY_P8 APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_ISSUER_ID; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is required" >&2
    exit 1
  fi
done

if [[ ! -f "$PKG" ]]; then
  echo "ERROR: Package not found: $PKG" >&2
  exit 1
fi

# altool looks for AuthKey_<KEYID>.p8 in ~/.appstoreconnect/private_keys
KEY_DIR="$HOME/.appstoreconnect/private_keys"
KEY_FILE="$KEY_DIR/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"
(umask 077 && printf '%s\n' "$APP_STORE_CONNECT_API_KEY_P8" > "$KEY_FILE")
trap 'rm -f "$KEY_FILE"' EXIT

echo "==> Validating $PKG"
xcrun altool --validate-app -f "$PKG" --type macos \
  --apiKey "$APP_STORE_CONNECT_KEY_ID" --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"

echo "==> Uploading $PKG to App Store Connect"
xcrun altool --upload-app -f "$PKG" --type macos \
  --apiKey "$APP_STORE_CONNECT_KEY_ID" --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"

echo "==> Upload complete. The build will appear in App Store Connect after processing."
