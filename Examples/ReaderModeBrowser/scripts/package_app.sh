#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ReaderModeBrowser"
BUNDLE_ID="com.example.readermodebrowser"
BUILD_MODE="${1:-debug}"

if [[ "${BUILD_MODE}" != "debug" && "${BUILD_MODE}" != "release" ]]; then
  echo "Usage: $(basename "$0") [debug|release]" >&2
  exit 1
fi

cd "${ROOT_DIR}"

export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/swiftpm-module-cache"
export XDG_CACHE_HOME="${TMPDIR:-/tmp}/swiftpm-cache"
export SWIFTPM_DISABLE_SANDBOX=1

swift build -c "${BUILD_MODE}"

BUILD_DIR="${ROOT_DIR}/.build/${BUILD_MODE}"
PRODUCT_PATH="${BUILD_DIR}/${APP_NAME}"
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

if [[ ! -f "${PRODUCT_PATH}" ]]; then
  echo "ERROR: built product not found at ${PRODUCT_PATH}" >&2
  exit 1
fi

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${CONTENTS_DIR}/Resources"
cp "${PRODUCT_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>Reader Mode Browser</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true
fi

printf '%s\n' "${APP_BUNDLE}"
