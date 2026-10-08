#!/bin/zsh
set -euo pipefail

# Builds a universal, ad-hoc-signed test package. No Apple Developer account is required.
SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
TEMP_BUILD_DIR="$(mktemp -d /private/tmp/quadrant-package.XXXXXX)"
ARM_BUILD_DIR="${TEMP_BUILD_DIR}/arm64"
INTEL_BUILD_DIR="${TEMP_BUILD_DIR}/x86_64"
APP_DIR="${TEMP_BUILD_DIR}/序.app"
DIST_DIR="${PROJECT_DIR}/dist"
STAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -n "${RELEASE_VERSION:-}" ]]; then
  DMG_PATH="${DIST_DIR}/Xu-${RELEASE_VERSION}.dmg"
else
  DMG_PATH="${DIST_DIR}/序-unsigned-${STAMP}.dmg"
fi

cd "${PROJECT_DIR}"
mkdir -p "${DIST_DIR}" "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

# The desktop runner may not allow SwiftPM's nested sandbox to initialize.
# Keep the package build usable in that environment while retaining the
# temporary scratch directories for isolation.
swift build --disable-sandbox -c release --arch arm64 --scratch-path "${ARM_BUILD_DIR}"
swift build --disable-sandbox -c release --arch x86_64 --scratch-path "${INTEL_BUILD_DIR}"

lipo -create \
  "${ARM_BUILD_DIR}/arm64-apple-macosx/release/Quadrant" \
  "${INTEL_BUILD_DIR}/x86_64-apple-macosx/release/Quadrant" \
  -output "${APP_DIR}/Contents/MacOS/Quadrant"

cp "${PROJECT_DIR}/Packaging/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${PROJECT_DIR}/Assets/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
cp "${PROJECT_DIR}/Packaging/INSTALL-TEST.md" "${APP_DIR}/Contents/Resources/安装说明.md"
codesign --force --deep --sign - "${APP_DIR}"

hdiutil create -volname "序" -srcfolder "${APP_DIR}" -format UDZO -ov "${DMG_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
spctl --assess --type execute --verbose=2 "${APP_DIR}" || true

print "\n内测包已生成：${DMG_PATH}"
print "应用程序包：${APP_DIR}"
