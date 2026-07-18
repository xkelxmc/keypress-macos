#!/usr/bin/env bash
set -euo pipefail

# Validate that the changelog is ready for release
# Usage: ./Scripts/validate_changelog.sh <version> [changelog-file]

VERSION=${1:?"usage: $0 <version> [changelog-file]"}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
CHANGELOG=${2:-CHANGELOG.md}

# Accept both "## 0.1.0 - date" and Keep-a-Changelog "## [0.1.0] - date"
first_line=$(grep -m1 '^## ' "$CHANGELOG" | sed -E 's/^## +//; s/^\[([^]]+)\]/\1/')
if [[ "$first_line" != ${VERSION}* ]]; then
  echo "ERROR: Top CHANGELOG section is '$first_line' but expected '${VERSION} — …'" >&2
  exit 1
fi

grep -qE "^## \[?${VERSION}\]?( |$)" "$CHANGELOG" || {
  echo "ERROR: No section for version ${VERSION} in ${CHANGELOG}" >&2
  exit 1
}

grep -qi 'Unreleased' "$CHANGELOG" && grep -m1 '^## ' "$CHANGELOG" | grep -qi 'Unreleased' && {
  echo "ERROR: Top section still labeled Unreleased; finalize changelog first." >&2
  exit 1
}

echo "Changelog OK for ${VERSION}"
