#!/usr/bin/env bash
# 把 dist/OneMarkdown.app 安装到 /Applications 并刷新 LaunchServices 注册
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -d dist/OneMarkdown.app ]] || { echo "先执行 scripts/build.sh" >&2; exit 1; }
if pgrep -x OneMarkdown >/dev/null; then osascript -e 'tell application "OneMarkdown" to quit' || true; sleep 1; fi
rm -rf /Applications/OneMarkdown.app
cp -R dist/OneMarkdown.app /Applications/
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# 注销 dist/ 副本，避免 Finder“打开方式”里出现两个 OneMarkdown
"$LSR" -u "$PWD/dist/OneMarkdown.app" >/dev/null 2>&1 || true
"$LSR" -f /Applications/OneMarkdown.app
echo "已安装 /Applications/OneMarkdown.app"
