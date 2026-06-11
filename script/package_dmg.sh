#!/usr/bin/env bash
set -euo pipefail

APP_NAME="typeart"
VERSION="${1:-0.1.4}"
DMG_NAME="${APP_NAME}-v${VERSION}-macos.dmg"
DMG_PATH="dist/${DMG_NAME}"
CHECKSUM_PATH="${DMG_PATH}.sha256"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STAGING_DIR=""
RW_DMG=""

cleanup() {
  if [[ -n "${STAGING_DIR}" && -d "${STAGING_DIR}" ]]; then
    rm -rf "${STAGING_DIR}"
  fi
  if [[ -n "${RW_DMG}" && -f "${RW_DMG}" ]]; then
    rm -f "${RW_DMG}"
  fi
}
trap cleanup EXIT

cd "${REPO_ROOT}"

# Reuse the release app packaging flow so the .app metadata stays consistent.
"${SCRIPT_DIR}/package_release.sh" "${VERSION}"

APP_BUNDLE="dist/${APP_NAME}.app"
if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "Missing ${APP_BUNDLE}" >&2
  exit 1
fi

rm -f "${DMG_PATH}" "${CHECKSUM_PATH}"
STAGING_DIR="$(mktemp -d)"
RW_DMG="dist/${APP_NAME}-v${VERSION}-rw.dmg"

cp -R "${APP_BUNDLE}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

# Create a read/write image first, then convert it to a compressed read-only DMG.
hdiutil create \
  -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "${STAGING_DIR}" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "${RW_DMG}" >/dev/null

hdiutil convert "${RW_DMG}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "${DMG_PATH}" >/dev/null

/usr/bin/shasum -a 256 "${DMG_PATH}" > "${CHECKSUM_PATH}"

echo "Created ${DMG_PATH}"
echo "Created ${CHECKSUM_PATH}"
