#!/usr/bin/env bash
# 下载渲染层第三方依赖到 OneMarkdown/Resources/Renderer/vendor/，并按 CHECKSUMS.txt 校验。
# 用法：scripts/fetch-vendor.sh            # 下载并校验
#       scripts/fetch-vendor.sh --update-checksums   # 首次/升级版本时重写校验文件
set -euo pipefail
cd "$(dirname "$0")/.."
VENDOR="OneMarkdown/Resources/Renderer/vendor"
mkdir -p "$VENDOR/LICENSES"

# 名称|URL（版本号写死，保证可复现）
DEPS=(
  "markdown-it.min.js|https://cdn.jsdelivr.net/npm/markdown-it@14.1.0/dist/markdown-it.min.js"
  "markdown-it-footnote.min.js|https://cdn.jsdelivr.net/npm/markdown-it-footnote@4.0.0/dist/markdown-it-footnote.min.js"
  "markdown-it-task-lists.min.js|https://cdn.jsdelivr.net/npm/markdown-it-task-lists@2.1.1/dist/markdown-it-task-lists.min.js"
  "markdown-it-anchor.umd.js|https://cdn.jsdelivr.net/npm/markdown-it-anchor@9.2.0/dist/markdownItAnchor.umd.js"
  "highlight.min.js|https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js"
  "github.min.css|https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github.min.css"
  "github-dark.min.css|https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github-dark.min.css"
  "github-markdown.min.css|https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.8.1/github-markdown.min.css"
  "purify.min.js|https://cdnjs.cloudflare.com/ajax/libs/dompurify/3.2.6/purify.min.js"
)
# 正文字体：Open Sans 可变字体（OFL 1.1），拉丁字符用它，中文回退系统苹方
FONTS=(
  "open-sans-latin-wght-normal.woff2|https://cdn.jsdelivr.net/npm/@fontsource-variable/open-sans@5.2.6/files/open-sans-latin-wght-normal.woff2"
  "open-sans-latin-wght-italic.woff2|https://cdn.jsdelivr.net/npm/@fontsource-variable/open-sans@5.2.6/files/open-sans-latin-wght-italic.woff2"
  "open-sans-latin-ext-wght-normal.woff2|https://cdn.jsdelivr.net/npm/@fontsource-variable/open-sans@5.2.6/files/open-sans-latin-ext-wght-normal.woff2"
)
LICENSES=(
  "markdown-it.LICENSE|https://cdn.jsdelivr.net/npm/markdown-it@14.1.0/LICENSE"
  "markdown-it-footnote.LICENSE|https://cdn.jsdelivr.net/npm/markdown-it-footnote@4.0.0/LICENSE"
  "markdown-it-task-lists.LICENSE|https://cdn.jsdelivr.net/npm/markdown-it-task-lists@2.1.1/LICENSE"
  "markdown-it-anchor.UNLICENSE|https://cdn.jsdelivr.net/npm/markdown-it-anchor@9.2.0/UNLICENSE"
  "highlight.js.LICENSE|https://cdn.jsdelivr.net/npm/highlight.js@11.11.1/LICENSE"
  "github-markdown-css.LICENSE|https://cdn.jsdelivr.net/npm/github-markdown-css@5.8.1/license"
  "dompurify.LICENSE|https://cdn.jsdelivr.net/npm/dompurify@3.2.6/LICENSE"
  "open-sans.OFL.txt|https://cdn.jsdelivr.net/npm/@fontsource-variable/open-sans@5.2.6/LICENSE"
)

for entry in "${DEPS[@]}"; do
  name="${entry%%|*}"; url="${entry#*|}"
  echo "→ $name"
  curl -fsSL --retry 3 -o "$VENDOR/$name" "$url"
done
mkdir -p "$VENDOR/fonts"
for entry in "${FONTS[@]}"; do
  name="${entry%%|*}"; url="${entry#*|}"
  echo "→ fonts/$name"
  curl -fsSL --retry 3 -o "$VENDOR/fonts/$name" "$url"
done
for entry in "${LICENSES[@]}"; do
  name="${entry%%|*}"; url="${entry#*|}"
  curl -fsSL --retry 3 -o "$VENDOR/LICENSES/$name" "$url" || echo "  (license $name 下载失败，跳过)"
done

if [[ "${1:-}" == "--update-checksums" ]]; then
  (cd "$VENDOR" && shasum -a 256 *.js *.css fonts/*.woff2 > CHECKSUMS.txt)
  echo "已重写 $VENDOR/CHECKSUMS.txt"
else
  (cd "$VENDOR" && shasum -a 256 -c CHECKSUMS.txt)
fi
echo "vendor OK"
