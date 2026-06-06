#!/usr/bin/env bash
set -euo pipefail

APP_NAME="lesstype"
EXECUTABLE_NAME="VoiceInputApp"
BUNDLE_DIR="dist/${APP_NAME}.app"
EXECUTABLE=".build/debug/${EXECUTABLE_NAME}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

matching_app_pids() {
  local bundle_executable="${REPO_ROOT}/${BUNDLE_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"
  local debug_executable="${REPO_ROOT}/${EXECUTABLE}"
  local found=1

  while read -r pid; do
    local executable_path
    executable_path="$(ps -p "${pid}" -o comm= || true)"

    if [[ "${executable_path}" == "${bundle_executable}" || "${executable_path}" == "${debug_executable}" ]]; then
      echo "${pid}"
      found=0
    fi
  done < <(pgrep -x "${EXECUTABLE_NAME}" || true)

  return "${found}"
}

running_pids="$(matching_app_pids || true)"
if [[ -n "${running_pids}" ]]; then
  while read -r pid; do
    kill "${pid}"
  done <<< "${running_pids}"
fi

swift build

rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
cp "${EXECUTABLE}" "${BUNDLE_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"

mkdir -p "${BUNDLE_DIR}/Contents/Resources"
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns"
elif [[ -f "Resources/AppIcon.png" ]]; then
  ICON_TMP_DIR="$(mktemp -d)"
  ICONSET_DIR="${ICON_TMP_DIR}/AppIcon.iconset"
  mkdir -p "${ICONSET_DIR}"
  sips -z 16 16 "Resources/AppIcon.png" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
  sips -z 32 32 "Resources/AppIcon.png" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "Resources/AppIcon.png" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
  sips -z 64 64 "Resources/AppIcon.png" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "Resources/AppIcon.png" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
  sips -z 256 256 "Resources/AppIcon.png" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "Resources/AppIcon.png" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
  sips -z 512 512 "Resources/AppIcon.png" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "Resources/AppIcon.png" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "Resources/AppIcon.png" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "${ICONSET_DIR}" -o "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns"
  rm -rf "${ICON_TMP_DIR}"
fi

cat > "${BUNDLE_DIR}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleExecutable</key>
  <string>VoiceInputApp</string>
  <key>CFBundleDisplayName</key>
  <string>lesstype</string>
  <key>CFBundleIdentifier</key>
  <string>app.lesstype.voiceinput</string>
  <key>CFBundleName</key>
  <string>lesstype</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>lesstype needs microphone access to record dictation.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>lesstype needs speech recognition access to convert speech to text.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --deep --sign - "${BUNDLE_DIR}" >/dev/null

if [[ "${1:-}" == "--verify" ]]; then
  /usr/bin/open -n "${BUNDLE_DIR}"
  sleep 2
  matching_app_pids >/dev/null
  running_pids="$(matching_app_pids || true)"
  if [[ -n "${running_pids}" ]]; then
    while read -r pid; do
      kill "${pid}"
    done <<< "${running_pids}"
  fi
  echo "Verified ${APP_NAME} launches"
else
  /usr/bin/open -n "${BUNDLE_DIR}"
fi
