#!/usr/bin/env bash
set -euo pipefail

APP_NAME="lesstype"
EXECUTABLE_NAME="VoiceInputApp"
VERSION="${1:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_DIR="dist/${APP_NAME}.app"
EXECUTABLE=".build/release/${EXECUTABLE_NAME}"
ZIP_PATH="dist/${APP_NAME}-v${VERSION}-macos.zip"
CHECKSUM_PATH="${ZIP_PATH}.sha256"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

swift build -c release

rm -rf "${BUNDLE_DIR}" "${ZIP_PATH}" "${CHECKSUM_PATH}"
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

cat > "${BUNDLE_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>app.lesstype.voiceinput</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
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

mkdir -p dist
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${BUNDLE_DIR}" "${ZIP_PATH}"
/usr/bin/shasum -a 256 "${ZIP_PATH}" > "${CHECKSUM_PATH}"

echo "Created ${ZIP_PATH}"
echo "Created ${CHECKSUM_PATH}"
