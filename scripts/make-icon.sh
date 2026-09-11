#!/usr/bin/env bash
# 生成应用图标：Swift 脚本画 1024 主图 → sips 缩放 10 个尺寸 → 写入 AppIcon.appiconset，并用 iconutil 合成 .icns
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/icon
ICONSET="$OUT/OneMarkdown.iconset"
APPICONSET=OneMarkdown/Resources/Assets.xcassets/AppIcon.appiconset
mkdir -p "$OUT" "$ICONSET"

swift scripts/generate_app_icon.swift "$OUT/icon_1024.png"
swift scripts/generate_app_icon.swift "$OUT/icon_1024_simple.png" --simple

# 尺寸:文件名:来源（16/32 两档用简化版，保证小图可辨）
SPECS=(
  "16:icon_16x16:simple"
  "32:icon_16x16@2x:simple"
  "32:icon_32x32:simple"
  "64:icon_32x32@2x:full"
  "128:icon_128x128:full"
  "256:icon_128x128@2x:full"
  "256:icon_256x256:full"
  "512:icon_256x256@2x:full"
  "512:icon_512x512:full"
  "1024:icon_512x512@2x:full"
)
for spec in "${SPECS[@]}"; do
  IFS=: read -r sz name src <<<"$spec"
  if [[ "$src" == "simple" ]]; then srcfile="$OUT/icon_1024_simple.png"; else srcfile="$OUT/icon_1024.png"; fi
  sips -z "$sz" "$sz" "$srcfile" --out "$ICONSET/$name.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT/OneMarkdown.icns"
cp "$ICONSET"/*.png "$APPICONSET/"
echo "icon OK → $APPICONSET, $OUT/OneMarkdown.icns"
