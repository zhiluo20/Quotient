#!/bin/zsh
# 生成 Xcode 工程并构建 Quotient.app（含桌面小组件扩展）到 dist/，同时产出可分发 zip
set -e
set -o pipefail
cd "$(dirname "$0")"

VERSION=1.0.3

xcodegen generate

xcodebuild -project Quotient.xcodeproj \
  -scheme Quotient \
  -configuration Release \
  -derivedDataPath .build/DerivedData \
  build | tail -5

rm -rf dist/Quotient.app "dist/Quotient-$VERSION.zip"
mkdir -p dist
cp -R .build/DerivedData/Build/Products/Release/Quotient.app dist/

ditto -c -k --keepParent dist/Quotient.app "dist/Quotient-$VERSION.zip"

# 注销 DerivedData 里的构建产物注册，避免与已安装副本出现同 bundle id
# 的重复注册（会让桌面小组件绑到错误的扩展、配置项不显示）
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for app in \
  .build/DerivedData/Build/Products/Release/Quotient.app \
  .build/DerivedData/Build/Products/Debug/Quotient.app \
  dist/Quotient.app
do
  "$LSREG" -u "$app" 2>/dev/null || true
done

echo "✅ 构建完成: dist/Quotient.app"
echo "📦 分发包:   dist/Quotient-$VERSION.zip"
echo "   打开方式: open dist/Quotient.app"
echo "   提示: 安装到 /Applications 后再用；改动小组件配置后需删除桌面旧组件再重新添加。"
