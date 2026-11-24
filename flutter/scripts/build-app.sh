#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
REPO_DIR="${PROJECT_DIR:h}"
CONFIGURATION="debug"
UNIVERSAL=false
RESOLVE_PACKAGES=true
OUTPUT_APP="${REPO_DIR}/dist/序.app"
while (( $# > 0 )); do
  case "$1" in
    --release) CONFIGURATION="release" ;;
    --universal) UNIVERSAL=true ;;
    --no-pub) RESOLVE_PACKAGES=false ;;
    --output) shift; OUTPUT_APP="$1" ;;
    *) print -u2 "未知参数：$1"; exit 1 ;;
  esac
  shift
done
cd "${PROJECT_DIR}"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PROJECT_DIR}/Packaging/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PROJECT_DIR}/Packaging/Info.plist")"
if [[ "${RESOLVE_PACKAGES}" == true ]]; then
  fvm flutter pub get
fi
fvm flutter build macos --${CONFIGURATION} --no-pub --build-name "${APP_VERSION}" --build-number "${BUILD_NUMBER}"
SOURCE_APP="${PROJECT_DIR}/build/macos/Build/Products/${CONFIGURATION:u}/序.app"
[[ -d "${SOURCE_APP}" ]] || { print -u2 "Flutter 构建产物不存在：${SOURCE_APP}"; exit 1; }
if [[ "${UNIVERSAL}" == true ]]; then
  ARCHS="$(lipo -archs "${SOURCE_APP}/Contents/MacOS/序")"
  [[ " ${ARCHS} " == *" arm64 "* && " ${ARCHS} " == *" x86_64 "* ]] || { print -u2 "产物不是通用架构：${ARCHS}"; exit 1; }
fi
mkdir -p "${OUTPUT_APP:h}"
rm -rf "${OUTPUT_APP}"
ditto "${SOURCE_APP}" "${OUTPUT_APP}"
if [[ "${CONFIGURATION}" == "release" ]]; then
  ENTITLEMENTS="${PROJECT_DIR}/macos/Runner/Release.entitlements"
else
  ENTITLEMENTS="${PROJECT_DIR}/macos/Runner/DebugProfile.entitlements"
fi
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  for FRAMEWORK in "${OUTPUT_APP}"/Contents/Frameworks/*.framework; do
    codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${FRAMEWORK}"
  done
  codesign --force --options runtime --timestamp --entitlements "${ENTITLEMENTS}" --sign "${SIGNING_IDENTITY}" "${OUTPUT_APP}"
else
  cp "${PROJECT_DIR}/Packaging/INSTALL-TEST.md" "${OUTPUT_APP}/Contents/Resources/安装说明.md"
  codesign --force --entitlements "${ENTITLEMENTS}" --sign - "${OUTPUT_APP}"
fi
codesign --verify --deep --strict "${OUTPUT_APP}"
print "应用已生成：${OUTPUT_APP}"
