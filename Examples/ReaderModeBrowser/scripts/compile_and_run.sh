#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ReaderModeBrowser"
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
APP_PROCESS_PATTERN="${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
DEBUG_PROCESS_PATTERN="${ROOT_DIR}/.build/debug/${APP_NAME}"
RELEASE_PROCESS_PATTERN="${ROOT_DIR}/.build/release/${APP_NAME}"
BUILD_MODE="debug"

log() {
  printf '%s\n' "$*"
}

for arg in "$@"; do
  case "${arg}" in
    --release)
      BUILD_MODE="release"
      ;;
    --debug)
      BUILD_MODE="debug"
      ;;
    --help|-h)
      log "Usage: $(basename "$0") [--debug|--release]"
      exit 0
      ;;
    *)
      ;;
  esac
done

log "==> Killing existing ${APP_NAME} instances"
pkill -f "${APP_PROCESS_PATTERN}" 2>/dev/null || true
pkill -f "${DEBUG_PROCESS_PATTERN}" 2>/dev/null || true
pkill -f "${RELEASE_PROCESS_PATTERN}" 2>/dev/null || true
pkill -x "${APP_NAME}" 2>/dev/null || true

log "==> Packaging ${APP_NAME} (${BUILD_MODE})"
"${ROOT_DIR}/scripts/package_app.sh" "${BUILD_MODE}" >/dev/null

log "==> Launching ${APP_NAME}"
if ! open "${APP_BUNDLE}"; then
  log "WARN: open failed; falling back to direct launch."
  "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 &
  disown
fi

for _ in {1..12}; do
  if pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1; then
    log "OK: ${APP_NAME} is running."
    exit 0
  fi
  sleep 0.25
done

log "WARN: ${APP_NAME} did not appear to stay running. Check Console.app for crash logs."
exit 1
