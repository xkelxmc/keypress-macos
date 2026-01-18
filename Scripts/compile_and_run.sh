#!/usr/bin/env bash
# Reset Keypress: kill running instances, build, package, relaunch, verify.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${ROOT_DIR}/Keypress.app"
APP_NAME="Keypress"

log()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

run_step() {
  local label="$1"; shift
  log "==> ${label}"
  if ! "$@"; then
    fail "${label} failed"
  fi
}

kill_all_keypress() {
  pkill -x "${APP_NAME}" 2>/dev/null || true
  pkill -f "${APP_BUNDLE}" 2>/dev/null || true
  sleep 0.5
}

RUN_TESTS=0
for arg in "$@"; do
  case "${arg}" in
    --test|-t) RUN_TESTS=1 ;;
    --help|-h)
      log "Usage: $(basename "$0") [--test]"
      exit 0
      ;;
  esac
done

# 1) Kill running instances
log "==> Killing existing Keypress instances"
kill_all_keypress

# 2) Run tests if requested
if [[ "${RUN_TESTS}" == "1" ]]; then
  run_step "swift test" swift test -q
fi

# 3) Package
run_step "package app" "${ROOT_DIR}/Scripts/package_app.sh"

# 4) Launch
log "==> Launching app"
open "${APP_BUNDLE}"

# 5) Verify
sleep 1
if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
  log "OK: Keypress is running."
  exit 0
fi
fail "App exited immediately. Check Console.app for crash logs."
