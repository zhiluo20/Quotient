#!/bin/zsh
# 生成 Resources/AppIcon.icns
set -e
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
swift Scripts/make_icon.swift "$tmp/icon_1024.png"

iconset="$tmp/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size "$tmp/icon_1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$tmp/icon_1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p Resources
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
rm -rf "$tmp"
echo "✅ Resources/AppIcon.icns 已生成"
