#!/usr/bin/env bash
# Generate Sparkle appcast.xml from a release zip.
# Usage: ./Scripts/make_appcast.sh Keypress-0.1.0.zip
# Requires:
#   - SPARKLE_PRIVATE_KEY_FILE: Path to ed25519 private key
#   - generate_appcast: Sparkle CLI tool in PATH

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ZIP=${1:?"Usage: $0 Keypress-<version>.zip"}

if [[ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  echo "SPARKLE_PRIVATE_KEY_FILE is required (path to ed25519 private key)." >&2
  exit 1
fi

if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  echo "Sparkle key file not found: $SPARKLE_PRIVATE_KEY_FILE" >&2
  exit 1
fi

if [[ ! -f "$ZIP" ]]; then
  echo "Zip not found: $ZIP" >&2
  exit 1
fi

if ! command -v generate_appcast >/dev/null; then
  echo "generate_appcast not found. Install Sparkle tools." >&2
  exit 1
fi

# Extract version from filename
ZIP_NAME=$(basename "$ZIP")
if [[ "$ZIP_NAME" =~ ^Keypress-([0-9]+\.[0-9]+\.[0-9]+)\.zip$ ]]; then
  VERSION="${BASH_REMATCH[1]}"
else
  echo "Could not extract version from $ZIP_NAME" >&2
  exit 1
fi

# TODO: Update these URLs when you have a release location
FEED_URL=${SPARKLE_FEED_URL:-"https://raw.githubusercontent.com/xkelxmc/keypress-macos/main/appcast.xml"}
DOWNLOAD_URL_PREFIX=${SPARKLE_DOWNLOAD_URL_PREFIX:-"https://github.com/xkelxmc/keypress-macos/releases/download/v${VERSION}/"}

WORK_DIR=$(mktemp -d /tmp/keypress-appcast.XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

cp "$ROOT/appcast.xml" "$WORK_DIR/appcast.xml" 2>/dev/null || touch "$WORK_DIR/appcast.xml"
cp "$ZIP" "$WORK_DIR/$ZIP_NAME"

pushd "$WORK_DIR" >/dev/null
generate_appcast \
  --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --link "$FEED_URL" \
  "$WORK_DIR"
popd >/dev/null

cp "$WORK_DIR/appcast.xml" "$ROOT/appcast.xml"

echo "Appcast updated: appcast.xml"
echo "Upload $ZIP to $DOWNLOAD_URL_PREFIX"
