#!/usr/bin/env bash
set -euo pipefail

# Full release workflow for Keypress
# Prerequisites:
#   - Clean git worktree
#   - CHANGELOG.md finalized for the version
#   - SPARKLE_PRIVATE_KEY_FILE set
#   - APP_IDENTITY, APP_STORE_CONNECT_* env vars for notarization

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"

APP_NAME="Keypress"
TAG="v${MARKETING_VERSION}"
ZIP_NAME="${APP_NAME}-${MARKETING_VERSION}.zip"

err() { echo "ERROR: $*" >&2; exit 1; }

echo "==> Releasing ${APP_NAME} ${MARKETING_VERSION}"

# 1. Check for clean worktree
if [[ -n "$(git status --porcelain)" ]]; then
  err "Working directory not clean. Commit or stash changes first."
fi

# 2. Validate changelog
"$ROOT/Scripts/validate_changelog.sh" "$MARKETING_VERSION"

# 3. Lint and test
echo "==> Running lint and tests"
swiftformat Sources Tests --lint || err "SwiftFormat failed"
swiftlint --strict || err "SwiftLint failed"
swift test || err "Tests failed"

# 4. Sign and notarize
echo "==> Building, signing, and notarizing"
"$ROOT/Scripts/sign-and-notarize.sh"

# 5. Create git tag
echo "==> Creating tag $TAG"
git tag -f "$TAG"
git push -f origin "$TAG"

# 6. Create GitHub release
echo "==> Creating GitHub release"
NOTES=$(awk "/^## \[?${MARKETING_VERSION}\]?/{found=1;next} /^## /{found=0} found" CHANGELOG.md)
gh release create "$TAG" "$ZIP_NAME" \
  --title "${APP_NAME} ${MARKETING_VERSION}" \
  --notes "$NOTES"

# 7. Update appcast (if Sparkle key is available)
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  echo "==> Updating appcast"
  "$ROOT/Scripts/make_appcast.sh" "$ZIP_NAME"

  git add appcast.xml
  git commit -m "docs: update appcast for ${MARKETING_VERSION}"
  git push origin main
fi

echo ""
echo "==> Release ${MARKETING_VERSION} complete!"
echo "    GitHub: https://github.com/xkelxmc/keypress-macos/releases/tag/${TAG}"
