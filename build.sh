#!/bin/zsh
# 生成 Xcode 工程并构建 Quotient.app（含桌面小组件扩展）到 dist/，同时产出可分发 zip
set -e
cd "$(dirname "$0")"

VERSION=1.0.0

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

echo "✅ 构建完成: dist/Quotient.app"
echo "📦 分发包:   dist/Quotient-$VERSION.zip"
echo "   打开方式: open dist/Quotient.app"
