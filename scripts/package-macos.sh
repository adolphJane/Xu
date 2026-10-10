#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
TEMP_BUILD_DIR="$(mktemp -d /private/tmp/quadrant-package.XXXXXX)"
trap 'rm -rf "${TEMP_BUILD_DIR}"' EXIT
ARM_BUILD_DIR="${TEMP_BUILD_DIR}/arm64"
INTEL_BUILD_DIR="${TEMP_BUILD_DIR}/x86_64"
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

cd "${PROJECT_DIR}"
mkdir -p "${DIST_DIR}" "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources" "${DMG_ROOT}"

swift build --disable-sandbox -c release --arch arm64 --scratch-path "${ARM_BUILD_DIR}"
swift build --disable-sandbox -c release --arch x86_64 --scratch-path "${INTEL_BUILD_DIR}"

lipo -create \
  "${ARM_BUILD_DIR}/arm64-apple-macosx/release/Quadrant" \
  "${INTEL_BUILD_DIR}/x86_64-apple-macosx/release/Quadrant" \
  -output "${APP_DIR}/Contents/MacOS/Quadrant"

cp "${PROJECT_DIR}/Packaging/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${PROJECT_DIR}/Assets/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${APP_DIR}"
else
  cp "${PROJECT_DIR}/Packaging/INSTALL-TEST.md" "${APP_DIR}/Contents/Resources/安装说明.md"
  codesign --force --sign - "${APP_DIR}"
fi
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

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
