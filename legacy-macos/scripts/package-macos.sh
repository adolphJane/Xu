#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
TEMP_BUILD_DIR="$(mktemp -d /private/tmp/quadrant-package.XXXXXX)"
trap 'rm -rf "${TEMP_BUILD_DIR}"' EXIT
APP_DIR="${TEMP_BUILD_DIR}/序.app"
DMG_ROOT="${TEMP_BUILD_DIR}/dmg"
DIST_DIR="${PROJECT_DIR}/dist"
STAMP="$(date +%Y%m%d-%H%M%S)"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PROJECT_DIR}/Packaging/Info.plist")"
RELEASE_NAME="${RELEASE_VERSION:-v${APP_VERSION}-local-${STAMP}}"
DMG_PATH="${DIST_DIR}/Xu-${RELEASE_NAME}.dmg"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  if [[ -z "${NOTARY_API_KEY_PATH:-}" || -z "${NOTARY_KEY_ID:-}" || -z "${NOTARY_ISSUER_ID:-}" ]]; then
    print -u2 "Developer ID 打包需要完整的 Apple 公证凭据。"
    exit 1
  fi
fi

mkdir -p "${DIST_DIR}" "${DMG_ROOT}"
"${SCRIPT_DIR}/build-app.sh" --release --universal --output "${APP_DIR}"

cp -R "${APP_DIR}" "${DMG_ROOT}/序.app"
ln -s /Applications "${DMG_ROOT}/Applications"
if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
  cp "${PROJECT_DIR}/Packaging/INSTALL-TEST.md" "${DMG_ROOT}/安装说明.md"
fi
hdiutil create -volname "序" -srcfolder "${DMG_ROOT}" -format UDZO -ov "${DMG_PATH}"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  NOTARY_RESULT="$(xcrun notarytool submit "${DMG_PATH}" \
    --key "${NOTARY_API_KEY_PATH}" \
    --key-id "${NOTARY_KEY_ID}" \
    --issuer "${NOTARY_ISSUER_ID}" \
    --wait --output-format json)"
  if ! print -r -- "${NOTARY_RESULT}" | jq -e '.status == "Accepted"' > /dev/null; then
    print -u2 "Apple 公证未通过：$(print -r -- "${NOTARY_RESULT}" | jq -r '.status // "Unknown"')"
    exit 1
  fi
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler validate "${DMG_PATH}"
  print "已完成 Developer ID 签名和 Apple 公证：${DMG_PATH}"
else
  print "内测包已生成（临时签名，macOS 会显示安全提示）：${DMG_PATH}"
fi
