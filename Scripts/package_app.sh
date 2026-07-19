#!/usr/bin/env bash
# Package Keypress.app for local development.
# Builds through the same Xcode project as the App Store release
# (project.yml + xcodegen), so dev and store builds cannot drift apart.
# SPM (Package.swift) remains for code organization and `swift test`.
#
# Usage: ./Scripts/package_app.sh [release|debug]

set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"

APP_NAME="Keypress"

case "$CONF" in
  release) CONF_TITLE="Release" ;;
  debug) CONF_TITLE="Debug" ;;
  *) echo "ERROR: unknown configuration '$CONF' (use release or debug)" >&2; exit 1 ;;
esac

command -v xcodegen >/dev/null || {
  echo "ERROR: xcodegen is required (brew install xcodegen)" >&2
  exit 1
}

xcodegen generate --use-cache

DERIVED=".build/xcode"
xcodebuild build -quiet \
  -project "${APP_NAME}.xcodeproj" -scheme "$APP_NAME" -configuration "$CONF_TITLE" \
  -derivedDataPath "$DERIVED" -destination "platform=macOS,arch=$(uname -m)" \
  MARKETING_VERSION="$MARKETING_VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ONLY_ACTIVE_ARCH=YES

APP_SRC="$DERIVED/Build/Products/$CONF_TITLE/${APP_NAME}.app"
rm -rf "${APP_NAME}.app"
ditto "$APP_SRC" "${APP_NAME}.app"

echo "Created $ROOT/${APP_NAME}.app"
