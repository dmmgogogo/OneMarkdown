#!/usr/bin/env bash
# 构建 Release 版 OneMarkdown.app 到 dist/，ad-hoc 签名并校验。
# 用法：scripts/build.sh [--test] [--universal]
set -euo pipefail
cd "$(dirname "$0")/.."

RUN_TESTS=0
ARCH_ARGS=(-destination 'platform=macOS,arch=arm64')
EXTRA_SETTINGS=()
for arg in "$@"; do
  case "$arg" in
    --test) RUN_TESTS=1 ;;
    --universal) ARCH_ARGS=(-destination 'generic/platform=macOS'); EXTRA_SETTINGS+=('ARCHS=arm64 x86_64') ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

VERSION=$(grep -E '^\s+MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
DERIVED=build/DerivedData
mkdir -p build

if [[ ! -f OneMarkdown/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png ]]; then
  echo "缺少图标，先执行 scripts/make-icon.sh" >&2; exit 1
fi
if [[ ! -f OneMarkdown/Resources/Renderer/vendor/markdown-it.min.js ]]; then
  echo "缺少 vendor，先执行 scripts/fetch-vendor.sh" >&2; exit 1
fi

xcodegen generate --quiet

# 完整日志写入文件；失败时打印 error 行并以非零退出，避免旧产物被误打包
run_xcodebuild() {
  if ! xcodebuild "$@" > "$LOG" 2>&1; then
    grep -E 'error:|\*\* .* FAILED|Executed .* failures' "$LOG" | sort -u | head -40 >&2
    echo "xcodebuild 失败，完整日志见 $LOG" >&2
    return 1
  fi
}

if [[ $RUN_TESTS -eq 1 ]]; then
  echo "▶ 运行单元测试"
  LOG=build/xcodebuild-test.log
  run_xcodebuild test -project OneMarkdown.xcodeproj -scheme OneMarkdown \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=""
  grep -E "Test Suite 'All tests'|Executed [0-9]+ tests" "$LOG" | tail -2
fi

echo "▶ 构建 Release"
LOG=build/xcodebuild-build.log
# 先清掉上一次的产物，保证 dist 里一定是本次构建
rm -rf "$DERIVED/Build/Products/Release/OneMarkdown.app"
run_xcodebuild -project OneMarkdown.xcodeproj -scheme OneMarkdown -configuration Release \
  "${ARCH_ARGS[@]}" -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" ${EXTRA_SETTINGS[@]+"${EXTRA_SETTINGS[@]}"} \
  build
grep -E '\*\* BUILD' "$LOG" | tail -1

APP="$DERIVED/Build/Products/Release/OneMarkdown.app"
[[ -d "$APP" ]] || { echo "构建失败：找不到 $APP" >&2; exit 1; }

rm -rf dist && mkdir -p dist
cp -R "$APP" dist/
codesign --force --deep --sign - --options runtime --timestamp=none dist/OneMarkdown.app
codesign --verify --deep --strict --verbose=2 dist/OneMarkdown.app
codesign -dv --verbose=2 dist/OneMarkdown.app 2>&1 | grep -E '^(Identifier|Signature|CodeDirectory)' || true
echo "OK dist/OneMarkdown.app ($VERSION)"
