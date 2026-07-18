#!/usr/bin/env bash
# Build, sign, and notarize Keypress.app for distribution.
# Produces Keypress-<version>.zip (universal binary, notarized, stapled).
#
# Required env:
#   APP_IDENTITY                  Developer ID Application identity name
#   APP_STORE_CONNECT_API_KEY_P8  App Store Connect API key content (.p8)
#   APP_STORE_CONNECT_KEY_ID      API key ID
#   APP_STORE_CONNECT_ISSUER_ID   Issuer ID

set -euo pipefail

APP_NAME="Keypress"
APP_BUNDLE="Keypress.app"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"

ZIP_NAME="${APP_NAME}-${MARKETING_VERSION}.zip"

for var in APP_IDENTITY APP_STORE_CONNECT_API_KEY_P8 APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_ISSUER_ID; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is required" >&2
    exit 1
  fi
done

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

API_KEY_FILE="$WORK_DIR/api-key.p8"
printf '%s\n' "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > "$API_KEY_FILE"
NOTARY_ARGS=(--key "$API_KEY_FILE" --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID")

# Universal release build + app bundle
echo "==> Building universal binary"
ARCHES=${ARCHES:-"arm64 x86_64"} ./Scripts/package_app.sh release
lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Sign inside-out: notarization rejects any nested binary without a Developer ID
# signature, so every Sparkle component must be re-signed before the app itself.
echo "==> Signing with $APP_IDENTITY"
SIGN=(codesign --force --timestamp --options runtime --sign "$APP_IDENTITY")
SPARKLE="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
  "${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
  "${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
  "${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
  "${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
  "${SIGN[@]}" "$SPARKLE"
fi
"${SIGN[@]}" "$APP_BUNDLE"

codesign --verify --deep --strict "$APP_BUNDLE"

# Submit for notarization. notarytool's exit code is unreliable for rejected
# submissions, so parse the JSON status and fetch the log on failure.
echo "==> Submitting for notarization"
ditto -c -k --keepParent "$APP_BUNDLE" "$WORK_DIR/notarize.zip"
set +e
SUBMIT_JSON=$(xcrun notarytool submit "$WORK_DIR/notarize.zip" "${NOTARY_ARGS[@]}" --wait --output-format json 2>&1)
SUBMIT_RC=$?
set -e
echo "$SUBMIT_JSON"

SUBMISSION_ID=$(echo "$SUBMIT_JSON" | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -1)
if ! echo "$SUBMIT_JSON" | grep -q '"status" *: *"Accepted"'; then
  echo "ERROR: Notarization was not accepted (exit code $SUBMIT_RC)" >&2
  if [[ -n "$SUBMISSION_ID" ]]; then
    echo "==> Notarization log:" >&2
    xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_ARGS[@]}" >&2 || true
  fi
  exit 1
fi

echo "==> Stapling ticket"
xcrun stapler staple "$APP_BUNDLE"

# Final distribution zip
rm -f "$ZIP_NAME"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_NAME"

echo "==> Verifying"
spctl -a -t exec -vv "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

echo "Done: $ZIP_NAME"
