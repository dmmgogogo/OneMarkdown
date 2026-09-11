#!/usr/bin/env bash
# 把 dist/OneMarkdown.app 打包成 dist/OneMarkdown-<version>.dmg（含 Applications 软链）
set -euo pipefail
cd "$(dirname "$0")/.."

APP=dist/OneMarkdown.app
[[ -d "$APP" ]] || { echo "先执行 scripts/build.sh" >&2; exit 1; }
VERSION=$(grep -E '^\s+MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
VOL=OneMarkdown
DMG="dist/OneMarkdown-${VERSION}.dmg"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
if [[ -f build/icon/OneMarkdown.icns ]]; then
  cp build/icon/OneMarkdown.icns "$STAGE/.VolumeIcon.icns"
  xcrun SetFile -a C "$STAGE" 2>/dev/null || true
fi

rm -f "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO -imagekey zlib-level=9 -fs HFS+ "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

MNT=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG" >/dev/null
if [[ -d "$MNT/OneMarkdown.app" && -L "$MNT/Applications" ]]; then
  echo "DMG layout OK"
else
  echo "DMG 内容不完整" >&2; hdiutil detach "$MNT" >/dev/null; exit 1
fi
hdiutil detach "$MNT" >/dev/null
codesign --sign - "$DMG" 2>/dev/null || true
ls -lh "$DMG"
