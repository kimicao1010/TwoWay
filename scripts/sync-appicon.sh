#!/bin/bash
#
# 同步 App 图标：源图目录（根目录 `2way.iconset/`）→ Asset Catalog
#
# 为什么要这个脚本：图标有两份（源图 + 资源目录里的副本），
# 直接改源图不会生效（actool 只读 Asset Catalog）→ 典型「换了图标但 App 还是旧的」坑。
# 每次更新源图后执行本脚本，再重新构建即可。
#
# 用法：bash scripts/sync-appicon.sh
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$PROJECT_DIR/2way.iconset"
DEST_DIR="$PROJECT_DIR/Sources/Resources/Assets.xcassets/AppIcon.appiconset"

[ -d "$SOURCE_DIR" ] || { echo "缺少源图目录：$SOURCE_DIR" >&2; exit 1; }
[ -d "$DEST_DIR" ] || { echo "缺少资源目录：$DEST_DIR" >&2; exit 1; }

COUNT=0
for file in "$SOURCE_DIR"/*.png; do
    cp "$file" "$DEST_DIR/"
    COUNT=$((COUNT + 1))
done

echo "已同步 $COUNT 个尺寸：$SOURCE_DIR → $DEST_DIR"
echo "提示：图标内容变更后需重新构建（xcodegen + xcodebuild）；Finder/Dock 图标缓存必要时用 killall Dock 刷新"
