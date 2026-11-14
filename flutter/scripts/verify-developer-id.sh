#!/bin/zsh
set -euo pipefail

APP_PATH="${1:?用法：verify-developer-id.sh 序.app Xu.dmg}"
DMG_PATH="${2:?用法：verify-developer-id.sh 序.app Xu.dmg}"
[[ -d "$APP_PATH" && -f "$DMG_PATH" ]] || { print -u2 "签名验证产物不存在"; exit 1; }

ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/序")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || {
  print -u2 "应用不是 Apple Silicon 与 Intel 双架构：$ARCHS"
  exit 1
}

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNATURE="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
[[ "$SIGNATURE" == *"Authority=Developer ID Application:"* ]] || {
  print -u2 "应用未使用 Developer ID Application 证书签名"
  exit 1
}
[[ "$SIGNATURE" == *"Runtime Version="* ]] || {
  print -u2 "应用未启用 Hardened Runtime"
  exit 1
}
xcrun stapler validate "$DMG_PATH"

MOUNT="$(mktemp -d /private/tmp/xu-notary-check.XXXXXX)"
trap 'hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true; rmdir "$MOUNT" >/dev/null 2>&1 || true' EXIT
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT" -nobrowse -readonly -quiet
codesign --verify --deep --strict "$MOUNT/序.app"
spctl --assess --type execute --verbose=4 "$MOUNT/序.app"
print "Developer ID、双架构、Hardened Runtime、Apple 公证和 DMG 内应用验证通过"
