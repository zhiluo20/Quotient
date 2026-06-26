#!/bin/zsh
# 把 dist/Quotient.app 打包成带「拖到 Applications」的 DMG。
# 未公证：用户首次打开需右键 →「打开」放行一次（见 README）。
set -e
cd "$(dirname "$0")/.."

VERSION=1.0.3
APP=dist/Quotient.app
DMG="dist/Quotient-$VERSION.dmg"

[ -d "$APP" ] || { echo "❌ 未找到 $APP，请先运行 ./build.sh"; exit 1; }

stage=$(mktemp -d)
cp -R "$APP" "$stage/"
ln -s /Applications "$stage/Applications"   # 拖拽目标

rm -f "$DMG"
hdiutil create \
  -volname "Quotient" \
  -srcfolder "$stage" \
  -fs HFS+ \
  -format UDZO \
  -ov "$DMG" >/dev/null

rm -rf "$stage"

# 本地自签名（仅去掉「来源不明」的额外摩擦；未公证仍需用户右键打开）
codesign --force -s - "$DMG" 2>/dev/null || true

echo "✅ DMG 已生成: $DMG"
echo "   用户安装：双击 DMG → 把 Quotient 拖到 Applications → 首次右键「打开」放行一次"
