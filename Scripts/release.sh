#!/usr/bin/env bash
# Cut a release. Finalizes CHANGELOG.md, bumps version.env, commits, tags,
# and pushes. The tag push triggers .github/workflows/release.yml, which
# builds, signs, notarizes, publishes the GitHub release, and updates the
# Sparkle appcast.
#
# Usage: ./Scripts/release.sh <version>   (e.g. 0.2.0)

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

err() { echo "ERROR: $*" >&2; exit 1; }

VERSION=${1:?"usage: $0 <version> (e.g. 0.2.0)"}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || err "Version must be X.Y.Z, got '$VERSION'"

TAG="v${VERSION}"

# Preflight
[[ "$(git branch --show-current)" == "main" ]] || err "Releases are cut from main"
[[ -z "$(git status --porcelain)" ]] || err "Working directory not clean. Commit your changes first."

git fetch origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
  || err "Local main is not in sync with origin/main. Push or pull first."
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && err "Tag $TAG already exists"

source "$ROOT/version.env"
NEW_BUILD=$((BUILD_NUMBER + 1))

echo "==> Running checks and tests"
swiftformat Sources Tests --lint || err "SwiftFormat failed"
swiftlint --strict || err "SwiftLint failed"
swift test || err "Tests failed"

# Prepare changes in a staging dir; the real files are only touched after confirmation
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

sed "s/^## \[Unreleased\]/## [${VERSION}] - $(date +%Y-%m-%d)/" CHANGELOG.md > "$STAGE/CHANGELOG.md"
printf 'MARKETING_VERSION=%s\nBUILD_NUMBER=%s\n' "$VERSION" "$NEW_BUILD" > "$STAGE/version.env"
./Scripts/validate_changelog.sh "$VERSION" "$STAGE/CHANGELOG.md"

echo ""
echo "==> Release ${VERSION} (build ${NEW_BUILD})"
diff -u version.env "$STAGE/version.env" || true
diff -u CHANGELOG.md "$STAGE/CHANGELOG.md" || true
echo ""
read -r -p "Commit, tag ${TAG}, and push? [y/N] " answer
[[ "$answer" == [yY] ]] || err "Aborted, nothing changed"

cp "$STAGE/version.env" version.env
cp "$STAGE/CHANGELOG.md" CHANGELOG.md
git add version.env CHANGELOG.md
git commit -m "chore: release ${VERSION}"
git tag "$TAG"
git push origin main "$TAG"

echo ""
echo "==> Tag ${TAG} pushed. Waiting for the release workflow run..."
RUN_ID=""
for _ in $(seq 1 24); do
  RUN_ID=$(gh run list --workflow=release.yml --branch "$TAG" --limit 1 \
    --json databaseId -q '.[0].databaseId' 2>/dev/null || true)
  [[ -n "$RUN_ID" ]] && break
  sleep 5
done
if [[ -z "$RUN_ID" ]]; then
  err "Could not find the workflow run for ${TAG}. Check https://github.com/xkelxmc/keypress-macos/actions"
fi
# Fails (and so does this script) if the release workflow fails
gh run watch --exit-status "$RUN_ID"

echo ""
echo "==> Release ${VERSION} complete: https://github.com/xkelxmc/keypress-macos/releases/tag/${TAG}"
