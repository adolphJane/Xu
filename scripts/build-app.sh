#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="debug"
UNIVERSAL=false
OUTPUT_APP="${PROJECT_DIR}/dist/序.app"

while (( $# > 0 )); do
  case "$1" in
    --release) CONFIGURATION="release" ;;
    --universal) UNIVERSAL=true ;;
    --output)
      shift
      if (( $# == 0 )); then
        print -u2 "--output 需要指定 .app 路径。"
        exit 1
      fi
      OUTPUT_APP="$1"
      ;;
    *) print -u2 "未知参数：$1"; exit 1 ;;
  esac
  shift
done

if [[ "${OUTPUT_APP}" != *.app ]]; then
  print -u2 "输出路径必须以 .app 结尾。"
  exit 1
fi

TEMP_BUILD_DIR="$(mktemp -d /private/tmp/quadrant-app.XXXXXX)"
trap 'rm -rf "${TEMP_BUILD_DIR}"' EXIT
STAGED_APP="${TEMP_BUILD_DIR}/序.app"
mkdir -p "${STAGED_APP}/Contents/MacOS" "${STAGED_APP}/Contents/Resources"

cd "${PROJECT_DIR}"
if [[ "${UNIVERSAL}" == true ]]; then
  ARM_BUILD_DIR="${TEMP_BUILD_DIR}/arm64"
  INTEL_BUILD_DIR="${TEMP_BUILD_DIR}/x86_64"
  swift build --disable-sandbox -c "${CONFIGURATION}" --arch arm64 --scratch-path "${ARM_BUILD_DIR}"
  swift build --disable-sandbox -c "${CONFIGURATION}" --arch x86_64 --scratch-path "${INTEL_BUILD_DIR}"
  lipo -create \
    "${ARM_BUILD_DIR}/arm64-apple-macosx/${CONFIGURATION}/Quadrant" \
    "${INTEL_BUILD_DIR}/x86_64-apple-macosx/${CONFIGURATION}/Quadrant" \
    -output "${STAGED_APP}/Contents/MacOS/Quadrant"
else
  swift build --disable-sandbox -c "${CONFIGURATION}"
  BIN_DIR="$(swift build --show-bin-path -c "${CONFIGURATION}")"
  cp "${BIN_DIR}/Quadrant" "${STAGED_APP}/Contents/MacOS/Quadrant"
fi

cp "${PROJECT_DIR}/Packaging/Info.plist" "${STAGED_APP}/Contents/Info.plist"
cp "${PROJECT_DIR}/Assets/AppIcon.icns" "${STAGED_APP}/Contents/Resources/AppIcon.icns"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${STAGED_APP}"
else
  cp "${PROJECT_DIR}/Packaging/INSTALL-TEST.md" "${STAGED_APP}/Contents/Resources/安装说明.md"
  codesign --force --sign - "${STAGED_APP}"
fi
codesign --verify --deep --strict --verbose=2 "${STAGED_APP}"

mkdir -p "${OUTPUT_APP:h}"
if [[ -e "${OUTPUT_APP}" ]]; then
  rm -rf "${OUTPUT_APP}"
fi
ditto "${STAGED_APP}" "${OUTPUT_APP}"
print "应用已生成：${OUTPUT_APP}"
