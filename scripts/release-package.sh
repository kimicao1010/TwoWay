#!/bin/bash
#
# 2way Release 打包
#
# 流程（沿用 TunnelManager 既有纪律）：
#   archive → 全组件自底向上重签 → 校验 DR → hdiutil 制作 UDZO → 校验 → 挂载实测
#
# 关键约束（TECH_PLAN §9 / D5）：
#   必须用自签证书「2way Local Signing」签名，禁止 ad-hoc。
#   ad-hoc 的 designated requirement 是 cdhash，每次重建都变。
#   （D9 起密钥存储为加密文件，不依赖 Keychain ACL；DR 锚定仍有价值：
#    未来若回归 Keychain，或用作身份锚点，均需要稳定的 DR。）
#
# 用法：bash scripts/release-package.sh
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

IDENTITY="${SIGNING_IDENTITY:-2way Local Signing}"
SCHEME="TwoWay"
APP_NAME="2way"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
ARCHIVE="$BUILD_DIR/2way.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
STAGE_DIR="$BUILD_DIR/dmg-stage"
VOL_NAME="2way"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

VERSION="$(grep -E '^\s+MARKETING_VERSION:' project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')"
[ -n "$VERSION" ] || fail "无法从 project.yml 读取 MARKETING_VERSION"
DMG="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

bold "==> [0/7] 前置检查"
security find-identity -p codesigning 2>/dev/null | grep -qF "$IDENTITY" \
  || fail "找不到签名身份「$IDENTITY」。先执行：bash scripts/create-signing-cert.sh"
echo "  签名身份：$IDENTITY"
echo "  版本：$VERSION"

bold "==> [1/7] xcodegen 生成工程"
xcodegen generate >/dev/null
echo "  完成"

bold "==> [2/7] Archive（Release）"
rm -rf "$ARCHIVE" "$EXPORT_DIR" "$STAGE_DIR"
xcodebuild archive \
  -project TwoWay.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  | tail -3
[ -d "$ARCHIVE" ] || fail "archive 失败"

APP_SRC="$ARCHIVE/Contents/Products/Applications/${APP_NAME}.app"
[ -d "$APP_SRC" ] || APP_SRC="$ARCHIVE/Products/Applications/${APP_NAME}.app"
[ -d "$APP_SRC" ] || fail "在 archive 中找不到 ${APP_NAME}.app"

mkdir -p "$EXPORT_DIR"
cp -R "$APP_SRC" "$EXPORT_DIR/"
APP="$EXPORT_DIR/${APP_NAME}.app"

bold "==> [3/7] 全组件自底向上重签"
# 由内向外：先签所有嵌套的可执行体与 bundle，最后签外层 app
find "$APP/Contents" -depth \( -name "*.dylib" -o -name "*.so" -o -name "*.framework" -o -name "*.bundle" \) -print0 2>/dev/null \
  | while IFS= read -r -d '' item; do
      codesign --force --timestamp=none --sign "$IDENTITY" "$item" 2>/dev/null || true
    done
find "$APP/Contents/MacOS" -type f -perm -111 -print0 2>/dev/null \
  | while IFS= read -r -d '' item; do
      codesign --force --timestamp=none --sign "$IDENTITY" "$item" 2>/dev/null || true
    done
codesign --force --timestamp=none --sign "$IDENTITY" "$APP"
echo "  重签完成"

bold "==> [4/7] 校验签名与 DR"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/  /'
DR="$(codesign -d -r- "$APP" 2>&1 | grep -i designated || true)"
echo "  DR: $DR"
if echo "$DR" | grep -q 'cdhash H"'; then
  fail "❌ DR 仍是 cdhash —— 签名身份没生效，回退成了 ad-hoc。检查 CODE_SIGN_IDENTITY 与证书是否在钥匙串里。"
fi
echo "$DR" | grep -q "$IDENTITY\|certificate root" \
  || fail "❌ DR 形态异常，未见证书锚点"
bold "  ✅ DR 已锚定证书，重建不影响 Keychain 授权"

bold "==> [5/7] 制作 DMG（UDZO）"
mkdir -p "$DIST_DIR" "$STAGE_DIR"
cp -R "$APP" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE_DIR" \
  -ov -format UDZO "$DMG" >/dev/null
echo "  产物：$DMG ($(du -h "$DMG" | cut -f1))"

bold "==> [6/7] 校验 DMG"
hdiutil verify "$DMG" 2>&1 | tail -2 | sed 's/^/  /'

bold "==> [7/7] 挂载实测"
MOUNT_PT="$(mktemp -d)"
hdiutil attach "$DMG" -mountpoint "$MOUNT_PT" -nobrowse -quiet
if [ -d "$MOUNT_PT/${APP_NAME}.app" ]; then
  echo "  ✅ 挂载成功，内含 ${APP_NAME}.app"
  codesign --verify --verbose=1 "$MOUNT_PT/${APP_NAME}.app" 2>&1 | sed 's/^/  /' || true
  echo "  DR: $(codesign -d -r- "$MOUNT_PT/${APP_NAME}.app" 2>&1 | grep -i designated || echo '(读取失败)')"
else
  hdiutil detach "$MOUNT_PT" -quiet || true
  fail "❌ 挂载后找不到 ${APP_NAME}.app"
fi
hdiutil detach "$MOUNT_PT" -quiet
rmdir "$MOUNT_PT" 2>/dev/null || true

echo
bold "打包完成：$DMG"
echo "  提示：本机构建的产物无 quarantine 属性，可直接运行；"
echo "       经 AirDrop / 网盘传到另一台机器会被 Gatekeeper 隔离，需右键打开或"
echo "       xattr -dr com.apple.quarantine <App>。自签证书无法公证。"
