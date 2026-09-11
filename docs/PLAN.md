# OneMarkdown — macOS 原生 Markdown 只读查看器 实施方案

- 文档状态：v1（规划稿，供 Opus 5 直接照做）
- 日期：2026-09-11
- 标注约定：`[已知]` = 有官方文档 / 本机核实 / 成熟惯例支撑；`[推测]` = 未实测或 macOS 26 上行为可能有变，实施时需验证。

---

## 0. 结论速览（TL;DR）

| 项 | 决定 |
|---|---|
| 产品名 / Bundle ID | `OneMarkdown` / `com.iamxmm.onemarkdown` |
| 最低系统 / 架构 | macOS 14.0 / 仅 arm64（可选加 x86_64 出 universal） |
| 技术栈 | SwiftUI App 生命周期（单 `Window` scene）+ AppKit 补位（`NSApplicationDelegateAdaptor`、`NSOpenPanel`、`NSWorkspace`）+ `WKWebView` 渲染 |
| Markdown 渲染 | 本地打包 **markdown-it 14** + footnote / task-lists / anchor 插件 + **highlight.js 11** + **github-markdown-css 5** + **DOMPurify 3**；运行时零联网 |
| 文档模型 | **不用 NSDocument / DocumentGroup**；自管 `WorkspaceViewModel`（根目录 + 当前文件 + 大纲） |
| 本地图片访问 | `loadFileURL(index.html, allowingReadAccessTo: "/")` + JS 把相对路径改写成绝对 `file://`；备选自定义 `WKURLSchemeHandler` |
| 工程组织 | **xcodegen** `project.yml` → `.xcodeproj`（与你现有 `ai-skill-manage` 惯例一致），纯命令行 build |
| 签名 / 沙盒 | ad-hoc（`codesign --sign -`）；**App Sandbox 关**、Hardened Runtime 开 |
| 打包 | `hdiutil create -format UDZO`，卷内含 `OneMarkdown.app` + `Applications` 软链 |
| 图标 | `scripts/generate_app_icon.swift`（CoreGraphics 画 1024 主图）→ `sips` 缩放 → `AppIcon.appiconset`；同时 `iconutil` 出 `.icns` 供 DMG 卷图标 |
| 代码规模估算 | Swift ≈ 2,300 行、JS/CSS/HTML ≈ 500 行、脚本 ≈ 300 行、测试 ≈ 250 行 |

---

## 1. 目标理解

做一个**只读**的 macOS 原生 Markdown 查看器，替代 Typora 的"看文档"场景：

1. 双击 / 拖拽 / `open -a` / ⌘O 打开 `.md` 文件，GitHub 风格渲染（标题、行内代码、语法高亮代码块、表格、任务列表、脚注）。
2. 左侧边栏：文件树（只显示 Markdown 与目录、可折叠）与大纲（标题跳转）两种模式切换、文件名过滤、底部工具条；右侧内容区居中留白、顶部显示文档名。
3. 明暗跟随系统、文件变更自动刷新、外链走浏览器、相对 `.md` 链接 App 内切换、最近打开、窗口尺寸记忆。
4. 产出 `.dmg`，拖入 `/Applications` 即可使用；无 Developer ID，ad-hoc 签名；给出 Gatekeeper 处理说明。
5. 自制图标，不复用 Typora 任何代码 / 资源 / 图标。

**非目标**：编辑、导出 HTML/Word、云同步、插件系统、多标签页。

---

## 2. 当前现状（本机核实）

| 项 | 事实 | 依据 |
|---|---|---|
| 项目目录 | `/Users/mmx/Documents/work/Github/App-oneMarkdown` 为空，非 git 仓库 | `ls -la` |
| 工具链 | Xcode 26.4 (17E192)、Swift 6.3、SDK macosx26.4、xcodegen 2.45.4、node v22.21.1 | 命令核实 |
| 系统工具 | `iconutil` `sips` `hdiutil` `codesign` `spctl` 均在；`create-dmg` 未装 | `which` |
| 签名身份 | 仅 "Apple Development" 证书（2 个），**无 Developer ID**；对 Gatekeeper 而言与 ad-hoc 无差别，统一用 ad-hoc | `security find-identity` |
| Gatekeeper | `spctl --status` = assessments enabled | 命令核实 |
| 网络 | cdnjs / jsdelivr / registry.npmjs.org 可达 | `curl` 核实（见 §3.7 版本表） |
| 已有惯例 | `ai-skill-manage` 用 xcodegen + `xcodebuild -derivedDataPath build` + `scripts/generate_app_icon.swift`（AppKit 脚本画 1024 PNG）+ `AppIcon.appiconset` 10 张 PNG | 读取该项目 |

**Typora 1.14.9 观察结论（仅作行为参考，不复制任何内容）**：

- `Contents/Resources/TypeMark/` 内是 HTML/JS 渲染包（codemirror、MathJax4、diagram），主程序 3.3 MB —— 印证"原生壳 + WKWebView + 本地 JS 渲染"路线 `[已知]`。
- 签名 entitlements 只有 `allow-jit / allow-unsigned-executable-memory / allow-dyld-environment-variables`，**没有 `com.apple.security.app-sandbox`** → Typora 不开沙盒 `[已知]`。
- 文档类型注册：`CFBundleDocumentTypes` 一条 Markdown（`LSItemContentTypes` = 自有 UTI + `net.daringfireball.markdown`，`LSHandlerRank: Owner`，扩展名 md/markdown/mmd/mdown/mkd/mdwn/mdtxt/mdtext/rmarkdown/rmd/apib/qmd/mdx）、一条 Plain Text（Alternate）、一条 `public.folder`（Viewer, Alternate，用于把文件夹拖到 Dock 图标）；`UTImportedTypeDeclarations` 里导入 `net.daringfireball.markdown`（conformsTo `public.plain-text`，mime `text/markdown`）`[已知]`。
- `LSMinimumSystemVersion` 11.0，`LSApplicationCategoryType` productivity。

---

## 3. 关键决策与理由

### 3.1 技术栈：SwiftUI 壳 + WKWebView 渲染（推荐），不用纯 Swift 渲染

| 方案 | 表格 | 代码高亮 | 任务列表 | 脚注 | 数学公式 | 明暗主题 | 工作量 | 结论 |
|---|---|---|---|---|---|---|---|---|
| **WKWebView + markdown-it + hljs + github-markdown-css** | 原生支持 | hljs 190+ 语言 | 插件 | 插件 | KaTeX 可选 | CSS `prefers-color-scheme` 自动 | 低 | **采用** |
| WKWebView + marked | 支持 | 需 marked-highlight | 内置 | 需 marked-footnote | 需自接 | 同上 | 低 | 备选；插件生态不如 markdown-it，heading id 也要额外扩展 |
| swift-markdown（Apple）+ NSAttributedString/NSTextView | 解析可、渲染需自写 | 需 Highlightr/Splash 自接 | 需自写 | 无 | 无 | 需自写 | 高 | 否决：表格在 NSTextView 渲染痛苦，视觉难对齐 GitHub/Typora |
| Textual/第三方 SwiftUI Markdown 库 | 弱 | 弱 | 弱 | 无 | 无 | — | 中 | 否决：表格/代码块质量达不到目标 |

理由：目标是"GitHub 风格 + 表格 + 高亮 + 大留白"，这正是 web 渲染栈最成熟的领域；Typora 自身也是这条路线。所有 JS/CSS 打包进 bundle，运行时不联网。

选 markdown-it 而非 marked 的具体原因：内置 `highlight` 钩子、`html: true/false` 开关、`linkify`；footnote / task-lists / anchor 三个插件都有 UMD 构建可直接 `<script>` 引入（已核实 jsdelivr 可下载）；VS Code 预览也基于 markdown-it `[已知]`。

### 3.2 窗口 / 文档模型：自管单窗口，不用 NSDocument 与 DocumentGroup

- `DocumentGroup` 面向"一个窗口一个可编辑文档"，需要 `FileDocument`/`ReferenceFileDocument`，与"文件夹侧栏 + 只读切换"的工作区模型不匹配；NSDocument 在 SwiftUI 生命周期下要写大量桥接代码，只为拿到"最近打开"和"双击打开"两个便利，不划算 `[已知]`。
- 采用 `@main struct OneMarkdownApp: App` + `Window("OneMarkdown", id: "main")`（单实例场景，macOS 13+ `[已知]`）+ `@NSApplicationDelegateAdaptor` 接收 `application(_:open:)`（Finder 双击 / Dock 拖入 / `open -a` 三条入口都走它 `[已知]`）。
- 单窗口的好处：文件打开事件路由唯一，无需"找当前 key window"；多窗口列为 P2（`WindowGroup(for: URL.self)`）。
- 窗口关闭后再打开文件：`AppDelegate` 通过 `AppState.openMainWindow` 闭包（由视图 `onAppear` 用 `@Environment(\.openWindow)` 注入）重新打开 `[已知模式]`；`applicationShouldHandleReopen(_:hasVisibleWindows:)` 返回 `true` 让 Dock 点击时恢复窗口 `[推测：SwiftUI Window scene 关闭后由此恢复，需实测]`。

### 3.3 渲染层与 Swift ↔ JS 协议

- `index.html` 只加载一次（`loadFileURL`），之后所有文档切换 / 热重载都通过 `webView.callAsyncJavaScript("return OneMD.render(payload)", arguments: ["payload": …], in: nil, in: .page)` 传参 —— 参数由 WebKit 序列化，**不需要手工转义**，也不会因为 `loadHTMLString` 重建页面而丢滚动位置 `[已知]`。
- JS → Swift 用 `WKScriptMessageHandler`（名字 `bridge`），消息类型见附录 A。
- 大纲在 JS 渲染完成后从 DOM 提取（`h1..h6` 的 level/text/id）回传，Swift 不再解析 Markdown，单一事实来源。

### 3.4 本地资源访问（图片相对路径）

问题：`loadFileURL(_:allowingReadAccessTo:)` 只放行一个目录树；`index.html` 在 bundle 里，用户图片在任意目录。

- **MVP 方案**：`webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))`，即放行整个文件系统读权限给 web 内容；JS 在渲染后把 `img[src] / a[href] / video[src] / source[src]` 中的相对路径（无 scheme、非 `#`）用 `new URL(v, baseHref)` 改写为绝对 `file://` URL，`baseHref` = 当前文档所在目录。`[已知：社区 Markdown 预览器常用做法；沙盒关闭时进程本来就能读全盘，不额外扩大攻击面]`
- **不要**用 `<base href>`：会把 `#anchor` 变成整页导航，且影响 CSP 判定。
- **备选（P2 加固）**：注册 `WKURLSchemeHandler`（scheme `omd`），`omd://app/…` 映射 bundle 渲染资源、`omd://file/<绝对路径>` 由 Swift 读盘并按扩展名白名单（png/jpg/jpeg/gif/webp/svg/bmp/tiff/heic/avif）返回。若 macOS 26 的 WebKit 对 `allowingReadAccessTo: /` 行为收紧（`[推测]`），切到这个方案，接口不变。
- 远程图片（`https://`）默认允许（与 Typora 一致），通过 CSP 限制只允许 `img-src`，脚本 / XHR / iframe 全部禁止（见 §11）。

### 3.5 项目组织与构建：xcodegen（推荐）

| 方案 | 优点 | 缺点 |
|---|---|---|
| **xcodegen `project.yml`** | 与现有项目一致；actool 编译 `.xcassets`、Info.plist 生成、测试 target、`xcodebuild test` 全套可用；`.xcodeproj` 可随时用 Xcode 打开调试 | 需要 `xcodegen generate`（一条命令） |
| SwiftPM executable + 手工拼 `.app` | 无 Xcode 工程 | 无 actool（图标要手工 `.icns` + `CFBundleIconFile`）、无测试 host、Info.plist 全手写、资源拷贝自写脚本；WKWebView bundle 资源路径要自己保证 |

结论：xcodegen。全流程命令：`xcodegen generate` → `xcodebuild … build` → `codesign` → `hdiutil`，见 §10；无需打开 Xcode GUI。

### 3.6 签名与沙盒

- **App Sandbox：关闭**。理由：(1) 不上架 App Store，不强制；(2) 开沙盒后"双击打开一个 .md"只获得该文件的读权限，同目录图片、相对链接的 `.md` 全部不可读，必须为每个目录做 security-scoped bookmark，体验倒退；(3) Typora 自身也不开沙盒 `[已知]`。WebKit 的 WebContent 进程本身仍受 WebKit 自带沙盒保护 `[已知]`。
- **Hardened Runtime：开启**（`ENABLE_HARDENED_RUNTIME: YES`），无需任何 entitlement：WKWebView 的 JS 在独立 XPC 进程执行，主进程不需要 `allow-jit` `[已知]`。若实测因 hardened runtime 报错，可降为 NO，不影响 ad-hoc 分发。
- **签名**：`CODE_SIGN_STYLE: Manual` + `CODE_SIGN_IDENTITY: "-"`；`build.sh` 结束时再 `codesign --force --deep --sign -` 一次并 `--verify --deep --strict`。ad-hoc 签名不含证书，可在任何 Mac 上运行，但 Gatekeeper 处理见 §15。

### 3.7 前端依赖与版本锁定（已核实可下载）

| 库 | 版本 | 下载 URL（fetch-vendor.sh 使用） | 大小 | 必需 |
|---|---|---|---|---|
| markdown-it | 14.1.0 | `https://cdn.jsdelivr.net/npm/markdown-it@14.1.0/dist/markdown-it.min.js` | 125 KB | 是 |
| markdown-it-footnote | 4.0.0 | `https://cdn.jsdelivr.net/npm/markdown-it-footnote@4.0.0/dist/markdown-it-footnote.min.js` | 6 KB | 是 |
| markdown-it-task-lists | 2.1.1 | `https://cdn.jsdelivr.net/npm/markdown-it-task-lists@2.1.1/dist/markdown-it-task-lists.min.js` | 3 KB | 是 |
| markdown-it-anchor | 9.2.0 | `https://cdn.jsdelivr.net/npm/markdown-it-anchor@9.2.0/dist/markdownItAnchor.umd.js` | 7 KB | 是 |
| highlight.js（common 子集） | 11.11.1 | `https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js` | 127 KB | 是 |
| highlight.js 主题 | 11.11.1 | 同路径 `styles/github.min.css`、`styles/github-dark.min.css` | 1 KB ×2 | 是 |
| github-markdown-css | 5.8.1 | `https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.8.1/github-markdown.min.css` | 26 KB | 是 |
| DOMPurify | 3.2.6 | `https://cdnjs.cloudflare.com/ajax/libs/dompurify/3.2.6/purify.min.js` | 22 KB | 是 |
| KaTeX | 0.16.x | `https://cdn.jsdelivr.net/npm/katex@0.16/dist/{katex.min.js,katex.min.css,contrib/auto-render.min.js}` + `fonts/`（用 `npm pack katex@0.16` 取 `dist/fonts`） | ≈1 MB | P2 |
| mermaid | 11.6.0 | cdnjs 可下（2.6 MB） | — | P2，默认不做 |

- 上表全部完整版本号 URL 已于 2026-09-11 `curl` 核实返回 200（anchor 最新为 10.0.0，但 9.2.0 的 UMD 路径已验证，锁 9.2.0 即可）；脚本里**写死完整版本号**，并把 sha256 记录到 `vendor/CHECKSUMS.txt`，脚本下载后校验。
- vendor 文件**提交进 git**，保证离线可构建、可复现。
- 许可证：markdown-it / hljs / DOMPurify(Apache-2.0 或 MPL 二选一) / github-markdown-css 均为 MIT 或等价宽松许可，在 `vendor/LICENSES/` 附上各自 LICENSE `[已知]`。

---

## 4. 功能范围与优先级

| 优先级 | 功能 | 快捷键 / 入口 | 验收要点 |
|---|---|---|---|
| **P0 必做** | 打开文件：⌘O 面板、Finder 双击、拖到窗口、拖到 Dock、`open -a` | ⌘O | 四条入口都能显示内容 |
| P0 | GitHub 风格渲染：H1–H6、行内代码、代码块高亮（bash/curl/json/js/yaml/py…）、表格、引用、列表、任务列表、脚注、图片、链接 | — | `samples/demo.md` 每个元素正确 |
| P0 | 侧栏文件树：打开文件夹、只显示 md + 目录、可折叠、点击切换、当前文件高亮 | ⌘⇧O 打开文件夹；⌘1 文件模式 | 1000 文件目录 < 1 s 建树 |
| P0 | 大纲视图：标题层级、点击跳转 | ⌘2 大纲模式 | 点击后对应标题滚到顶部 |
| P0 | 侧栏显示 / 隐藏 | ⌘⇧L（另保留系统默认 ⌃⌘S） | 状态保持 |
| P0 | 明暗主题跟随系统 | — | 切换外观即时生效，代码块主题同步 |
| P0 | 文件变更自动重载（含 vim/TextEdit 的原子替换写法），保持滚动位置 | — | `echo >>` 与 `mv` 覆盖都触发 |
| P0 | 相对路径图片、远程图片 | — | `images/a.png`、`../x.png`、`https://…` |
| P0 | 链接：http(s)/mailto → 系统浏览器；相对 `.md` → App 内打开；`#anchor` → 页内滚动；其他本地文件 → `NSWorkspace.open` | — | 四类各验一次 |
| P0 | 窗口标题 = 文件名（去扩展名），副标题 = 目录名 | — | — |
| P0 | 编码回退（UTF-8/BOM/GB18030/Big5/Shift-JIS）、大文件与二进制拒绝、文件被删提示 | — | 见 §11 |
| **P1 应做** | 正文查找（高亮、计数、上一个/下一个、Esc 关闭） | ⌘F / ⌘G / ⌘⇧G | "curl" 命中数正确 |
| P1 | 侧栏文件名过滤 | 侧栏搜索框 | 输入即过滤，保留目录层级 |
| P1 | 最近打开（10 条，去重，缺失文件灰显） | 文件 ▸ 最近打开 | 重启后仍在 |
| P1 | 窗口尺寸 / 位置记忆、侧栏展开状态、缩放级别记忆 | ⌘+ / ⌘- / ⌘0 | 重启后恢复 |
| P1 | 在 Finder 中显示、拷贝路径、刷新文件树、重新加载文档 | ⌘R 重载 | — |
| P1 | 空状态引导页（拖拽 / ⌘O） | — | — |
| **P2 加分** | 打印 / 导出 PDF | ⌘P / 文件 ▸ 导出 PDF… | PDF 可打开 |
| P2 | 数学公式（KaTeX） | — | `$…$` 与 `$$…$$` |
| P2 | 多窗口、递归 FSEvents 监听、自定义 scheme handler、全文搜索、mermaid、自定义 CSS | — | — |

---

## 5. 文件清单（路径 → 职责 → 规模估算）

```
App-oneMarkdown/
├── project.yml                          xcodegen 工程描述（§7）
├── .gitignore                           build/ dist/ *.xcodeproj xcuserdata .DS_Store
├── README.md                            使用说明、构建命令、Gatekeeper 说明（§15 原文）
├── docs/PLAN.md                         本文
├── samples/
│   ├── demo.md                          验收用样例：H1–H3、行内代码、bash/curl/json 代码块、表格、任务列表、脚注、相对图片、相对 md 链接、外链、锚点、原始 HTML、中文标题       (~120 行)
│   ├── sub/linked.md                    被 demo.md 相对链接的文档
│   └── images/demo.png                  相对路径图片（脚本生成一张纯色 PNG 即可）
├── OneMarkdown/
│   ├── App/
│   │   ├── OneMarkdownApp.swift         @main；Window(id:"main") scene；注入 AppState/VM；.commands { AppCommands }；.defaultSize          (~80)
│   │   ├── AppDelegate.swift            NSApplicationDelegate：application(_:open:) → AppState.enqueue；applicationShouldHandleReopen；applicationSupportsSecureRestorableState=true     (~70)
│   │   ├── AppCommands.swift            SwiftUI Commands：文件(打开… ⌘O / 打开文件夹… ⌘⇧O / 最近打开 / 在 Finder 中显示 / 重新加载 ⌘R / 导出 PDF… / 打印 ⌘P)；显示(侧栏 ⌘⇧L / 文件 ⌘1 / 大纲 ⌘2 / 放大缩小)；编辑(查找 ⌘F, 下一个 ⌘G, 上一个 ⌘⇧G)     (~130)
│   │   └── AppState.swift               @Observable 全局：pendingOpenURLs、openMainWindow 闭包、偏好(@AppStorage 键常量)     (~60)
│   ├── Models/
│   │   ├── FileNode.swift               树节点：id(url)、name、isDirectory、children:[FileNode]?；Identifiable/Hashable      (~50)
│   │   ├── OutlineItem.swift            level/text/id，Codable（与 JS 消息一致）     (~25)
│   │   ├── MarkdownDocument.swift       url、resolvedURL、text、encodingName、isLossy、byteCount、modifiedAt      (~50)
│   │   └── BridgeMessage.swift          JS→Swift 消息 enum（ready/outline/findResult/error/rendered）+ 解码      (~60)
│   ├── Services/
│   │   ├── MarkdownFileTypes.swift      扩展名集合、UTType 常量、isMarkdown(url)、ignoredDirectoryNames      (~40)
│   │   ├── DocumentLoader.swift         读文件：大小上限、二进制探测、BOM 去除、编码探测回退、CRLF 归一、符号链接解析      (~130)
│   │   ├── FileTreeBuilder.swift        目录枚举→FileNode：过滤/排序/深度与节点上限/剪掉无 md 的空目录/符号链接不递归      (~130)
│   │   ├── FileWatcher.swift            DispatchSource 单文件 + 目录监听；rename/delete 后轮询重挂；150 ms 去抖      (~120)
│   │   └── RecentFilesStore.swift       UserDefaults 最近 10 条；去重；存在性过滤；同步 NSDocumentController.noteNewRecentDocumentURL      (~60)
│   ├── ViewModels/
│   │   └── WorkspaceViewModel.swift     核心编排：rootFolder/currentDocument/tree/outline/sidebarMode/filterText/banner；open(url)/openFolder(url)/reload()/select(node)/consumePending()；持有 FileWatcher 与 RendererBridge 弱引用      (~240)
│   ├── Rendering/
│   │   ├── RendererBridge.swift         持有 WKWebView：配置、消息桥(弱代理)、导航策略、render()/scrollTo()/find()/zoom/print/pdf；ready 之前的渲染请求排队      (~230)
│   │   └── MarkdownWebView.swift        NSViewRepresentable，只负责把 bridge.webView 放进视图树      (~40)
│   ├── Views/
│   │   ├── MainWindowView.swift         NavigationSplitView(sidebar/detail) + 标题/副标题 + toolbar + .dropDestination(for: URL.self) + banner 覆盖层 + 空状态      (~130)
│   │   ├── Sidebar/
│   │   │   ├── SidebarView.swift        顶部 Picker(文件 | 大纲) + 搜索框；中间切换 FileTreeView/OutlineView；底部工具条（打开文件夹、⋮菜单：刷新/在 Finder 中显示/全部折叠、隐藏侧栏）      (~100)
│   │   │   ├── FileTreeView.swift       List(children:) 展示 FileNode；selection 绑定；右键菜单；过滤后的树      (~110)
│   │   │   └── OutlineView.swift        按 level 缩进的列表；点击 → vm.scrollTo(item)      (~60)
│   │   ├── Content/
│   │   │   ├── DocumentContentView.swift  MarkdownWebView + FindBar 叠放；无文档时 EmptyStateView      (~60)
│   │   │   ├── FindBarView.swift        输入框、计数、上/下一个、关闭；焦点管理      (~90)
│   │   │   └── EmptyStateView.swift     引导：拖入文件 / ⌘O / 打开文件夹按钮      (~50)
│   │   └── Components/
│   │       └── BannerView.swift         顶部提示条（info/warning/error，可关闭）      (~40)
│   └── Resources/
│       ├── Info.plist                   由 xcodegen 按 project.yml info.properties 生成（不要手改）
│       ├── Assets.xcassets/
│       │   ├── Contents.json
│       │   └── AppIcon.appiconset/      Contents.json + 10 张 PNG（make-icon.sh 生成）
│       └── Renderer/                    以 folder reference 打包 → Contents/Resources/Renderer/
│           ├── index.html               CSP meta、引入 vendor CSS/JS、<article class="markdown-body">、<script src="app.js">      (~40)
│           ├── app.js                   OneMD 命名空间：初始化 markdown-it/hljs、render()、路径改写、大纲提取、锚点点击、滚动保持、find、消息桥      (~280)
│           ├── theme.css                Typora 风格覆盖：居中宽度、留白、字体、代码块、表格、暗色、::highlight 样式、打印样式      (~160)
│           └── vendor/                  fetch-vendor.sh 下载；含 CHECKSUMS.txt、LICENSES/
├── OneMarkdownTests/
│   ├── DocumentLoaderTests.swift        UTF-8/BOM/GB18030/二进制/超大文件/CRLF      (~90)
│   ├── FileTreeBuilderTests.swift       过滤、排序、深度上限、空目录剪枝、符号链接循环、忽略目录      (~90)
│   ├── RecentFilesStoreTests.swift      去重、上限、缺失过滤（独立 UserDefaults suite）      (~50)
│   └── MarkdownFileTypesTests.swift     扩展名大小写、无扩展名      (~25)
└── scripts/
    ├── fetch-vendor.sh                  下载并校验 §3.7 依赖到 Resources/Renderer/vendor/      (~60)
    ├── generate_app_icon.swift          CoreGraphics 画 1024×1024 主图（§9）      (~150)
    ├── make-icon.sh                     调用上面脚本 → sips 缩放 10 尺寸 → 写 appiconset + iconutil 出 build/icon/OneMarkdown.icns      (~50)
    ├── build.sh                         xcodegen → xcodebuild Release → 拷贝到 dist/ → ad-hoc codesign → verify      (~60)
    ├── make-dmg.sh                      staging + Applications 软链 → hdiutil UDZO → verify → attach 冒烟 → detach      (~60)
    └── install-local.sh                 rm -rf /Applications/OneMarkdown.app && cp -R dist/… && lsregister -f（可选）      (~15)
```

---

## 6. 各模块实现要点

### 6.1 打开文件的四条入口（P0）

| 入口 | 机制 | 备注 |
|---|---|---|
| ⌘O | `NSOpenPanel`：`canChooseFiles = true`、`canChooseDirectories = true`、`allowsMultipleSelection = false`、`allowedContentTypes = [UTType("net.daringfireball.markdown")!, .folder]`、`allowsOtherFileTypes = true` | 选目录即"打开文件夹"；同一面板两用 `[已知]` |
| Finder 双击 / 打开方式 / Dock 拖入 / `open -a` | `AppDelegate.application(_ app: NSApplication, open urls: [URL])` → `AppState.pendingOpenURLs.append(contentsOf:)`；`MainWindowView.onChange(of: appState.pendingOpenURLs)` 与 `.task` 首次消费 | 冷启动时该回调可能早于视图挂载，所以必须走"待处理队列"而不是直接调 VM `[已知]` |
| 拖到窗口 | `.dropDestination(for: URL.self) { urls, _ in vm.open(urls.first) }`（macOS 13+ `[已知]`） | 目录 → openFolder，文件 → open |
| 拖到 Dock | 由 `CFBundleDocumentTypes` 注册决定；文件夹要能拖入需额外注册 `public.folder`（Viewer/Alternate，参考 Typora） | 同上走 `application(_:open:)` |

`VM.open(url)` 规则：目录 → `openFolder`；Markdown 文件 → 载入并设为当前；若 `rootFolder == nil` 或文件不在 `rootFolder` 之下，则把 `rootFolder` 设为该文件父目录（Typora 行为）；非 Markdown 文件 → banner "不是 Markdown 文件"（不交给 NSWorkspace 以免循环）。

### 6.2 文件树（P0）

- `FileTreeBuilder.build(root:) -> FileNode`：`FileManager.enumerator(at:includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey,.nameKey], options:[.skipsHiddenFiles,.skipsPackageDescendants])`；手动处理 `node_modules`、`.git`、`Library`、`Pods`、`DerivedData` 跳过（`skipDescendants()`）。
- 只保留 `isMarkdown(url)` 的文件与目录；构树后**剪掉不含任何 md 的目录**。
- 排序：目录在前，`localizedStandardCompare`（Finder 顺序）`[已知]`。
- 上限：深度 8、节点 5000；超限停止并 banner "目录过大，仅显示前 5000 项"。
- 符号链接目录：显示但不递归（记录 `resolvingSymlinksInPath()` 的真实路径集合防环）。
- 构树在 `Task.detached(priority: .userInitiated)` 中做，结果回主线程；期间侧栏显示 ProgressView。
- UI：`List(vm.filteredTree.children, children: \.children, selection: $vm.selectedNodeID)`，`[已知]` 自带折叠三角与键盘导航；过滤时用文件名 `localizedCaseInsensitiveContains`，保留匹配项祖先目录并自动展开。

### 6.3 大纲（P0）

- JS 渲染后抓 `article h1..h6` → `[{level, text(截 200 字), id}]` → `bridge.postMessage({type:'outline', items})`。
- 标题 id 由 markdown-it-anchor 生成，`slugify` 用 GitHub 规则：小写、去标点（保留中日韩字符与 `-`）、空格→`-`；重复标题自动加 `-1/-2`（anchor 插件自带 `uniqueSlugStartIndex`）`[已知]`。
- 点击大纲：`bridge.scrollTo(headingID:)` → JS `el.scrollIntoView({block:'start'})`，再向上偏移 16 px。
- 有大纲但当前文档为空 → 显示"无标题"。

### 6.4 文件变更监听（P0）

- `FileWatcher(url:)`：`open(path, O_EVTONLY)` → `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:[.write,.extend,.delete,.rename,.attrib],queue:)` `[已知]`。
- `.write/.extend/.attrib` → 150 ms 去抖 → `.modified`。
- `.delete/.rename`（TextEdit、vim、VS Code "安全写入"都会走原子替换）→ 取消 source、关闭 fd → 每 100 ms 轮询路径，最多 2 s：出现 → 重新挂载 + `.recreated`（触发重载）；未出现 → `.removed`（banner "文件已被删除或移动，显示的是最后一次内容"，继续每 2 s 轮询直到回来）。
- 目录监听：对 `rootFolder` 的 fd 同样挂 source（`.write` 表示条目增删 `[已知]`）→ 300 ms 去抖 → 重建树。只覆盖根目录一层；子目录变动靠"刷新"按钮（P2 用 `FSEventStreamCreate` 递归）。
- 重载时 `preserveScroll: true`，JS 记录并恢复 `scrollY`。

### 6.5 查找（P1）

- JS 实现：遍历 `article` 文本节点，`indexOf` 收集 `Range`，用 **CSS Custom Highlight API**（`CSS.highlights.set('omd-find', new Highlight(...ranges))` + `::highlight(omd-find)`）着色，不改动 DOM `[已知：Safari 17.2+ 支持，对应 macOS 14.2+]`；`CSS.highlights` 不存在时回退 `window.find()`。
- 当前项单独 `omd-find-current` 高亮并 `scrollIntoView({block:'center'})`；返回 `{current, total}`。
- Swift 侧 `FindBarView` 覆盖在内容区顶部右侧；Esc 关闭并 `clearFind()`。

### 6.6 主题（P0）

- `github-markdown-css` 默认构建自带 `@media (prefers-color-scheme: dark)` `[已知]`；hljs 用两个 `<link>`：`github.min.css media="(prefers-color-scheme: light)"`、`github-dark.min.css media="(prefers-color-scheme: dark)"`。
- WKWebView 自动把系统外观传给页面 `[已知]`；`webView.underPageBackgroundColor = .textBackgroundColor` 避免过滚动露白 / 露黑 `[已知 macOS 12+]`。
- `theme.css` 用 CSS 变量定义两套（浅色：背景 `#fff`，正文 `#1f2328`；深色：`#0d1117`/`#e6edf3`），覆盖 `.markdown-body` 的 `max-width: 860px; margin: 0 auto; padding: 48px 56px 120px; font-size: 16px; line-height: 1.65; font-family: -apple-system, "PingFang SC", "Helvetica Neue", sans-serif`；代码 `font-family: "SF Mono", Menlo, monospace; font-size: 14px`。

### 6.7 图片与链接（P0）

- 路径改写见 §3.4；`img` 加 `loading="lazy"`；图片加载失败显示占位（`onerror` 加 class 显示"图片未找到：path"）。
- 链接策略在 **两层**：JS 层拦截 `a[href^="#"]` 点击做页内滚动（`preventDefault`），其余交给 WebKit 导航；Swift `WKNavigationDelegate.decidePolicyFor`：
  - `navigationType == .linkActivated`：`http/https/mailto` → `NSWorkspace.shared.open(url)`、`.cancel`；`file://` 且 `isMarkdown` → `vm.open(url)`、`.cancel`；`file://` 其他 → `NSWorkspace.shared.open`、`.cancel`。
  - 其他类型：仅允许 `url.path == indexURL.path`（初次加载 / 重载），否则 `.cancel`。
- `webView.allowsBackForwardNavigationGestures = false`、`allowsLinkPreview = false`。

### 6.8 最近打开与窗口记忆（P1）

- `RecentFilesStore`：`UserDefaults` 键 `recentFiles: [String]`，前插、去重、截 10；菜单渲染时过滤不存在的路径（灰显 + 不可点）。同时调用 `NSDocumentController.shared.noteNewRecentDocumentURL(url)` 让 Dock 右键菜单也有 `[推测：非 NSDocument App 下 Dock 菜单是否显示需实测；不显示也不影响自有菜单]`。
- 窗口尺寸：SwiftUI `Window` scene 会按 scene id 自动持久化 frame `[已知]`；`.defaultSize(width: 1180, height: 800)` 只作首次。侧栏可见性 `columnVisibility` 用 `@AppStorage("sidebarVisible")` 驱动；列宽 `navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 420)`（列宽持久化由系统决定，`[推测]` 不保证）。
- 缩放：`webView.pageZoom`（macOS 11+ `[已知]`）存 `@AppStorage("pageZoom")`，范围 0.6–2.0，步进 0.1。

### 6.9 打印 / PDF（P2）

- 打印：`let op = webView.printOperation(with: printInfo)`（macOS 11+ `[已知]`）；社区已知坑：`op.view?.frame` 为零会打印空白，需先设 `op.view?.frame = NSRect(x: 0, y: 0, width: 595, height: 842)` 再 `op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)` `[推测：macOS 26 是否仍需该 workaround 未验证]`。
- 导出 PDF：分页版用同一 `NSPrintOperation` + `printInfo.jobDisposition = .save` + `printInfo.dictionary()[.jobSavingURL] = url`；快速版用 `webView.createPDF(configuration:)`（整页单张长图 `[已知]`）。默认给分页版，失败回退长图版。

---

## 7. `project.yml` 与 Info.plist 关键键值

```yaml
name: OneMarkdown
options:
  bundleIdPrefix: com.iamxmm
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
  generateEmptyDirectories: true

settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor      # Xcode 26 新设置，UI 类默认主线程隔离，少写 @MainActor [已知]
    SWIFT_APPROACHABLE_CONCURRENCY: YES          # Xcode 26 [已知]；若编译报并发错误过多，退回 SWIFT_VERSION "5"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    ARCHS: arm64                                 # 出 universal 改 "arm64 x86_64"
    ONLY_ACTIVE_ARCH: NO

targets:
  OneMarkdown:
    type: application
    platform: macOS
    sources:
      - path: OneMarkdown
        excludes:
          - "Resources/Renderer"                 # 避免与下面 folder reference 重复打包
      - path: OneMarkdown/Resources/Renderer
        type: folder                             # 蓝色文件夹引用，整目录原样拷入 Contents/Resources/Renderer/ [已知]
        buildPhase: resources
    info:
      path: OneMarkdown/Resources/Info.plist     # xcodegen 生成，自动填 CFBundleIdentifier/Version 等
      properties:
        CFBundleName: OneMarkdown
        CFBundleDisplayName: OneMarkdown
        NSPrincipalClass: NSApplication
        LSMinimumSystemVersion: "14.0"
        LSApplicationCategoryType: public.app-category.productivity
        NSHumanReadableCopyright: "Copyright © 2026 iamxmm. All rights reserved."
        NSHighResolutionCapable: true
        NSSupportsAutomaticTermination: false
        NSSupportsSuddenTermination: false
        NSAppTransportSecurity:
          NSAllowsArbitraryLoadsInWebContent: true   # 允许 http:// 远程图片；只要 https 可删掉 [已知]
        CFBundleDocumentTypes:
          - CFBundleTypeName: Markdown
            CFBundleTypeRole: Viewer
            LSHandlerRank: Default                    # Owner 会与 Typora 争默认；Default 既能出现在"打开方式"又不强抢
            LSItemContentTypes:
              - net.daringfireball.markdown
            CFBundleTypeExtensions: [md, markdown, mdown, mkd, mkdn, mdwn, mdtxt, mdtext, rmd, qmd, mdx]
          - CFBundleTypeName: Folder
            CFBundleTypeRole: Viewer
            LSHandlerRank: Alternate
            LSItemContentTypes:
              - public.folder
        UTImportedTypeDeclarations:
          - UTTypeIdentifier: net.daringfireball.markdown
            UTTypeDescription: Markdown
            UTTypeConformsTo: [public.plain-text]
            UTTypeTagSpecification:
              public.filename-extension: [md, markdown, mdown, mkd, mkdn, mdwn, mdtxt, mdtext, rmd, qmd, mdx]
              public.mime-type: [text/markdown]
    settings:
      base:
        PRODUCT_NAME: OneMarkdown
        PRODUCT_BUNDLE_IDENTIFIER: com.iamxmm.onemarkdown
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_STYLE: Manual
        CODE_SIGN_IDENTITY: "-"
        DEVELOPMENT_TEAM: ""
        ENABLE_HARDENED_RUNTIME: YES
        ENABLE_APP_SANDBOX: NO
        COMBINE_HIDPI_IMAGES: YES
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS: YES
        DEAD_CODE_STRIPPING: YES

  OneMarkdownTests:
    type: bundle.unit-test
    platform: macOS
    sources: [OneMarkdownTests]
    dependencies:
      - target: OneMarkdown
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/OneMarkdown.app/Contents/MacOS/OneMarkdown"

schemes:
  OneMarkdown:
    build:
      targets:
        OneMarkdown: all
        OneMarkdownTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets: [OneMarkdownTests]
    archive:
      config: Release
```

要点：
- `CFBundleIconFile/CFBundleIconName` 由 actool 的 partial Info.plist 自动合入（`ASSETCATALOG_COMPILER_APPICON_NAME`）`[已知]`；不必手写。
- `UTExportedTypeDeclarations` 不需要（我们不定义自有 UTI）；导入 `net.daringfireball.markdown` 即可与 Typora / 系统共存。
- Swift 6 语言模式 + Xcode 26 的 `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`：`FileWatcher` 的后台队列回调用 `Task { @MainActor in … }` 回主线程；被 `nonisolated` 标注的只有 `DocumentLoader`/`FileTreeBuilder` 的纯函数。若编译期并发错误堆积，**允许退回** `SWIFT_VERSION: "5"` + `SWIFT_STRICT_CONCURRENCY: minimal`，功能不受影响。

---

## 8. 渲染层设计（`Resources/Renderer/`）

### 8.1 `index.html`

```html
<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline';
               img-src file: data: blob: https: http:; font-src 'self' data:; media-src file:;
               connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'">
<link rel="stylesheet" href="vendor/github-markdown.min.css">
<link rel="stylesheet" href="vendor/github.min.css" media="(prefers-color-scheme: light)">
<link rel="stylesheet" href="vendor/github-dark.min.css" media="(prefers-color-scheme: dark)">
<link rel="stylesheet" href="theme.css">
</head><body>
<article id="content" class="markdown-body"></article>
<script src="vendor/markdown-it.min.js"></script> … 其余 vendor …
<script src="app.js"></script></body></html>
```

`[推测]` `file://` 源下 CSP `'self'` 的匹配在 WebKit 中可能不生效（file 源被视为 opaque）；若本地脚本被拦，改为 `script-src file:`、`style-src file: 'unsafe-inline'`，并在验收清单里明确验证"内联 `<script>` 不执行"。

### 8.2 `app.js`（`window.OneMD` 命名空间）

```js
const md = window.markdownit({ html: true, linkify: true, breaks: false, typographer: false,
  highlight(str, lang) {
    const l = ALIAS[lang] || lang;                       // curl/sh/shell/zsh→bash, yml→yaml, js→javascript, ts→typescript, py→python, json5→json
    if (l && hljs.getLanguage(l))
      return `<pre class="hljs"><code class="language-${l}">${hljs.highlight(str, {language: l, ignoreIllegals: true}).value}</code></pre>`;
    return `<pre class="hljs"><code>${md.utils.escapeHtml(str)}</code></pre>`;  // 未知语言不做 highlightAuto（慢且乱）
  }})
  .use(window.markdownitFootnote)
  .use(window.markdownitTaskLists, { label: true, enabled: false })
  .use(window.markdownItAnchor, { slugify: githubSlug, uniqueSlugStartIndex: 1 });
```

- `OneMD.render({ text, baseHref, docId, preserveScroll })`：
  1. `html = DOMPurify.sanitize(md.render(text), { USE_PROFILES: {html: true}, ADD_ATTR: ['id','class','align','width','height','start','checked','disabled','type'], FORBID_TAGS: ['script','iframe','object','embed','form'] })`（DOMPurify 默认已剔除 script/iframe，这里显式列出便于审计 `[已知]`；`<input type=checkbox>` 默认放行 `[推测：实施时用 demo.md 任务列表核对]`）。
  2. 记录 `scrollY`（同一 `docId` 且 `preserveScroll` 时用于恢复）→ `content.innerHTML = html`。
  3. 路径改写：对 `img[src], a[href], video[src], audio[src], source[src]`，若值不匹配 `/^[a-z][a-z0-9+.-]*:/i` 且不以 `#` 开头 → `new URL(v, baseHref).href`（`baseHref` 形如 `file:///Users/x/docs/`，以 `/` 开头的绝对路径也会正确变为 `file:///…`）。
  4. `img` 加 `loading="lazy"` 与 `onerror` 占位。
  5. 提取大纲 → `post({type:'outline', items})`；`post({type:'rendered', ms})`。
  6. 恢复滚动或 `scrollTo(0,0)`。
- `OneMD.scrollToHeading(id)`、`OneMD.find(query, {direction})`、`OneMD.clearFind()`、`OneMD.setFontSize(px)`（备用）。
- 全局 `click` 监听：`a[href^="#"]` → `preventDefault` + 页内滚动；其余放行给 WebKit 导航（Swift 决策）。
- `DOMContentLoaded` → `post({type:'ready'})`。
- `window.onerror` → `post({type:'error', message})`。

### 8.3 `theme.css` 要点

- 布局与字体（§6.6）；`h1` 底部 1 px 分隔线，`h2` 同（github-markdown-css 已有）；表格 `display: table; width: auto; max-width: 100%`，表头背景 `#f6f8fa` / 暗色 `#161b22`；代码块 `border-radius: 6px; padding: 16px; overflow-x: auto`；行内代码 `background: rgba(175,184,193,.2); padding: .2em .4em; border-radius: 6px`。
- `::highlight(omd-find){background:#fde047;color:#000}`、`::highlight(omd-find-current){background:#f97316;color:#fff}`。
- `@media print { .markdown-body { max-width: none; padding: 0 } }`。
- `img.omd-missing::after` 占位文案。

---

## 9. 图标生成方案

### 9.1 视觉设计（自制，不参考 Typora 的 T 字图标）

- 画布 1024×1024；主体为 824×824 的 squircle（内缩 100，圆角半径 ≈185，Big Sur 以来的标准比例，与你现有脚本一致 `[已知]`）。四周留透明边，**不要**画到画布边缘。
- 底色：纵向渐变 靛蓝 `#4C6FFF`（顶）→ `#2B3FD6`（底），上 45% 叠一层 `rgba(255,255,255,.10→0)` 高光。
- 主体：白色"纸页"（约 500×620，圆角 56，右上角折角 120，`rgba(0,0,0,.25)` 投影，y 偏移 -12、模糊 40），纸面上方三条浅灰 `#C9D1E0` 文本条（宽 60%/85%/50%，高 34，间距 60）表示"文档"。
- 符号：纸页下半部用系统粗体（`NSFont.systemFont(ofSize: 300, weight: .heavy)` 经 CoreText 绘制）画蓝色 "M"，右侧紧跟一个向下箭头（`CGPath` 画：竖线 + 三角），构成社区通用的 Markdown 标记 "M↓"（该标记为 CC0，且我们自行绘制 `[已知]`）。颜色用同一渐变。
- 小尺寸可读性：≤32 px 时纸页细节糊成一团但轮廓可辨；若验收觉得不清晰，脚本加 `--simple` 参数输出"仅底色 + 白色 M↓"的简化主图，用于 16/32 两档（Contents.json 可为不同尺寸指定不同文件）。
- **macOS 26 适配** `[推测]`：系统会把旧格式（`.icns`/appiconset）图标自动放入 Liquid Glass 容器并加玻璃质感；只要主体是标准 squircle、不透明、边缘不外溢，效果就正常。若实机 Dock 里效果不理想，用 Xcode 26 自带的 `Icon Composer.app`（`/Applications/Xcode.app/Contents/Applications/Icon Composer.app`，本机已存在）把同一 PNG/SVG 分层导出 `.icon` 包，放进 target 并把 `ASSETCATALOG_COMPILER_APPICON_NAME` 指向它；这是唯一需要 GUI 的可选步骤。

### 9.2 生成流程（`scripts/make-icon.sh`）

```bash
swift scripts/generate_app_icon.swift build/icon/icon_1024.png      # AppKit/CoreGraphics 脚本，~5 s
ICONSET=build/icon/OneMarkdown.iconset; mkdir -p "$ICONSET"
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
            128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 512:icon_256x256@2x \
            512:icon_512x512 1024:icon_512x512@2x; do
  sz=${spec%%:*}; name=${spec#*:}
  sips -z "$sz" "$sz" build/icon/icon_1024.png --out "$ICONSET/$name.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o build/icon/OneMarkdown.icns             # 供 DMG 卷图标 / 校验
cp "$ICONSET"/*.png OneMarkdown/Resources/Assets.xcassets/AppIcon.appiconset/
```

`AppIcon.appiconset/Contents.json` 直接复用 `ai-skill-manage` 的 10 项定义（16/32/128/256/512 各 1x/2x，`idiom: mac`）。

---

## 10. 构建与打包脚本

### 10.1 `scripts/fetch-vendor.sh`

- `set -euo pipefail`；对 §3.7 每个 `URL SHA256 目标文件名` 三元组循环：`curl -fsSL -o`，`shasum -a 256 -c` 校验；首次跑用 `--update-checksums` 写 `CHECKSUMS.txt`。
- 下载 LICENSE 到 `vendor/LICENSES/`。

### 10.2 `scripts/build.sh`

```bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep -E '^\s+MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
xcodegen generate --quiet
xcodebuild -project OneMarkdown.xcodeproj -scheme OneMarkdown -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  build 2>&1 | tail -20
rm -rf dist && mkdir -p dist
cp -R build/DerivedData/Build/Products/Release/OneMarkdown.app dist/
codesign --force --deep --sign - --timestamp=none dist/OneMarkdown.app        # 再签一次，覆盖任何后处理
codesign --verify --deep --strict --verbose=2 dist/OneMarkdown.app
codesign -dv --verbose=2 dist/OneMarkdown.app 2>&1 | grep -E 'Identifier|Signature|flags'
echo "OK dist/OneMarkdown.app ($VERSION)"
```

- 可选 `--universal`：`ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO`。
- 可选 `--test`：先跑 `xcodebuild test -scheme OneMarkdown -destination 'platform=macOS' -derivedDataPath build/DerivedData`。
- 用 `xcodebuild build` 而非 `archive + exportArchive`：后者需要 exportOptions 与签名配置，ad-hoc 场景多余 `[已知]`。

### 10.3 `scripts/make-dmg.sh`

```bash
set -euo pipefail
APP=dist/OneMarkdown.app; VOL=OneMarkdown; DMG="dist/OneMarkdown-${VERSION}.dmg"
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp build/icon/OneMarkdown.icns "$STAGE/.VolumeIcon.icns" 2>/dev/null && xcrun SetFile -a C "$STAGE" || true   # 卷图标，可选
rm -f "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO -imagekey zlib-level=9 -fs HFS+ "$DMG"
hdiutil verify "$DMG"
MNT=$(mktemp -d); hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG" >/dev/null
test -d "$MNT/OneMarkdown.app" && test -L "$MNT/Applications" && echo "DMG layout OK"
hdiutil detach "$MNT" >/dev/null
codesign --sign - "$DMG" || true          # 可选：给 DMG 也做 ad-hoc 签名
```

- `-fs HFS+` 兼容性最好（老系统也能挂载）`[已知]`；`UDZO` zlib 压缩，通用。
- 背景图 + 图标坐标排版需要 Finder AppleScript（`create-dmg` 的做法），列为 P2；MVP 交付纯净 DMG，用户看到两个图标：App 与 Applications 快捷方式，拖过去即可。

### 10.4 `scripts/install-local.sh`（可选）

```bash
rm -rf /Applications/OneMarkdown.app && cp -R dist/OneMarkdown.app /Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/OneMarkdown.app
```

---

## 11. 安全与边界

| 主题 | 策略 |
|---|---|
| 信任模型 | 本地文件、单用户桌面工具。Markdown 内容视为"半可信"：允许原始 HTML 排版（`html: true`），但**一律经 DOMPurify**：无 script / iframe / object / embed / form / `javascript:` / 事件属性。 |
| 网络 | CSP `connect-src 'none'; frame-src 'none'; script-src 仅本地`；只放行 `img-src https: http:`（远程图片）。App 自身不发起任何网络请求。远程图片会暴露 IP（与 Typora 相同），P2 可加"仅显示本地图片"偏好。 |
| 本地文件读取 | 沙盒关闭 + `allowingReadAccessTo: /`：页面能 `<img src="file:///etc/…">`，但没有脚本、没有网络，读到也无法外泄；SVG 通过 `<img>` 加载时脚本不执行 `[已知]`。P2 scheme handler 可进一步限制到图片扩展名白名单。 |
| 路径穿越 | 相对路径解析由 URL 标准化处理，`..` 允许（文档引用上级目录图片是正常需求）。文件树只在用户选定的根下枚举，不跟随符号链接递归。 |
| 大文件 | > 20 MB 拒绝（banner）；5–20 MB 提示"较大，渲染可能较慢"并继续；渲染在 JS 单线程，1 MB 级 Markdown 预期 < 500 ms。 |
| 编码 | 顺序：UTF-8（去 BOM）→ `NSString.stringEncoding(for:encodingOptions:convertedString:usedLossyConversion:)` 提示 `[utf8, gb18030, big5, shiftJIS, eucJP, windowsCP1252]` `[已知 API]` → 最后 `isoLatin1` 有损；非 UTF-8 时 banner 显示"以 GB 18030 解码"。 |
| 二进制 / 非 md | 前 8 KB 含 `\0` → 拒绝；扩展名不在列表但用户从 ⌘O 面板明确选择 → 仍按文本渲染（`allowsOtherFileTypes`）。 |
| 符号链接 | `URL.resolvingSymlinksInPath()` 取真实路径用于监听与最近列表；显示仍用原路径。 |
| 文件被删 / 移动 | 保留最后一次渲染 + banner；路径回来自动恢复；根目录被删 → 清空树 + banner。 |
| 权限弹窗 | 无沙盒但 macOS 仍有 TCC：首次读取 `~/Desktop`、`~/Documents`、`~/Downloads` 会弹系统授权（一次性）`[已知]`；用户拒绝 → 读文件报错 → banner 提示到"系统设置 › 隐私与安全性 › 文件和文件夹"开启。 |
| WebView 右键菜单 | 默认菜单含"重新载入"，无害；P2 可在 `WKWebView` 子类 `willOpenMenu(_:with:)` 中删除。 |
| 调试 | `#if DEBUG webView.isInspectable = true #endif`（macOS 13.3+ `[已知]`），Safari ▸ 开发 ▸ 可用 Web Inspector 调 app.js。 |

---

## 12. 验收清单（逐条可执行）

### 12.1 构建与产物

```bash
cd /Users/mmx/Documents/work/Github/App-oneMarkdown
scripts/fetch-vendor.sh && scripts/make-icon.sh && scripts/build.sh          # 期望：OK dist/OneMarkdown.app
xcodebuild test -project OneMarkdown.xcodeproj -scheme OneMarkdown -destination 'platform=macOS' -derivedDataPath build/DerivedData 2>&1 | grep -E 'Executed|TEST'   # 全绿
codesign -dv --verbose=2 dist/OneMarkdown.app 2>&1 | grep -E 'Signature=adhoc|flags=0x10000\(runtime\)'
codesign --verify --deep --strict dist/OneMarkdown.app && echo SIGN_OK
plutil -p dist/OneMarkdown.app/Contents/Info.plist | grep -E 'CFBundleIdentifier|LSMinimumSystemVersion|net.daringfireball|CFBundleIconFile'
ls dist/OneMarkdown.app/Contents/Resources/ | grep -E 'AppIcon.icns|Assets.car|Renderer'
ls dist/OneMarkdown.app/Contents/Resources/Renderer/vendor | wc -l          # ≥ 8
lipo -info dist/OneMarkdown.app/Contents/MacOS/OneMarkdown                 # arm64
otool -L dist/OneMarkdown.app/Contents/MacOS/OneMarkdown | grep -vE '/System|/usr/lib' ; echo "(应无第三方 dylib)"
```

### 12.2 功能（用 `samples/demo.md`）

| # | 操作 | 期望 |
|---|---|---|
| F1 | `open -a dist/OneMarkdown.app samples/demo.md` | 窗口出现，标题 "demo"，副标题 "samples"，正文渲染完整 |
| F2 | `open -a dist/OneMarkdown.app samples/` | 侧栏文件树显示 `demo.md`、`sub/linked.md`；`images/` 目录不出现（无 md） |
| F3 | Finder 双击 `demo.md`（先把 App 拷到 /Applications 或右键"打开方式"） | 同 F1；"打开方式"列表里出现 OneMarkdown |
| F4 | 把 `demo.md` 拖到窗口 / 拖到 Dock 图标 | 打开 |
| F5 | ⌘O 选择一个目录 | 等价 F2 |
| F6 | 渲染检查：H1–H3 层级、行内代码灰底、`bash`/`curl`/`json` 代码块着色、表格边框与表头加粗、任务列表勾选框、脚注跳转、`<details>` 原始 HTML 可展开、`<script>alert(1)</script>` **不执行** | 全部符合 |
| F7 | 图片：`images/demo.png`、`../samples/images/demo.png`、`https://…` 三种 | 前两张显示，远程显示（联网时）；不存在的图显示占位 |
| F8 | 链接：点外链 → 默认浏览器；点 `sub/linked.md` → App 内切换且侧栏高亮；点 `#二级标题` → 页内滚动；点 `.pdf` 本地文件 → 预览打开 | 四类符合 |
| F9 | 大纲：⌘2 切换，点击三级标题 | 内容滚到该标题；⌘1 切回文件树 |
| F10 | 侧栏：⌘⇧L 隐藏 / 显示；搜索框输 "link" | 只剩 `sub/linked.md` 且目录展开 |
| F11 | 热重载：`printf '\n## 新增标题\n' >> samples/demo.md` | 1 s 内出现新标题，滚动位置不变，大纲更新 |
| F12 | 原子替换：`cp samples/demo.md /tmp/d && mv /tmp/d samples/demo.md` | 仍能重载（监听未丢） |
| F13 | 删除：`mv samples/demo.md samples/demo.bak` → banner；`mv` 回来 | banner 消失并重载 |
| F14 | 编码：`iconv -f UTF-8 -t GB18030 samples/demo.md > /tmp/gbk.md && open -a dist/OneMarkdown.app /tmp/gbk.md` | 中文正常 + banner "以 GB 18030 解码" |
| F15 | 大文件：`head -c 30000000 /dev/urandom | base64 > /tmp/big.md` 打开 | 拒绝并提示；`yes '# t' | head -c 3000000 > /tmp/mid.md` 打开 < 3 s |
| F16 | 二进制：`open -a dist/OneMarkdown.app /bin/ls`（用 ⌘O 选） | 拒绝并提示 |
| F17 | 暗色：`osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to not dark mode'` | 正文与代码块主题即时切换；再执行一次切回 |
| F18 | ⌘F 输 "curl" | 高亮全部命中，计数 "1/3" 之类；⌘G/⌘⇧G 切换；Esc 关闭 |
| F19 | 最近打开：重启 App 后 文件 ▸ 最近打开 | 有 demo.md；删除文件后灰显 |
| F20 | 调整窗口大小与位置、隐藏侧栏、⌘+ 两次 → 退出重开 | 全部恢复 |
| F21 | ⌘P / 导出 PDF（P2） | 打印面板出现；PDF 文件可打开、分页正常 |
| F22 | 首次读取 `~/Downloads` 下的 md | 系统 TCC 弹窗，允许后正常 |

### 12.3 DMG 与 Gatekeeper

```bash
scripts/make-dmg.sh                                                # 期望：DMG layout OK
hdiutil imageinfo dist/OneMarkdown-0.1.0.dmg | grep -E 'Format:|Checksum'
open dist/OneMarkdown-0.1.0.dmg                                    # Finder 里看到 OneMarkdown.app + Applications
# 模拟"从网上下载"：
cp -R /Volumes/OneMarkdown/OneMarkdown.app /tmp/OM.app
xattr -w com.apple.quarantine "0083;$(printf '%x' $(date +%s));Safari;" /tmp/OM.app
open /tmp/OM.app                                                   # 期望：Gatekeeper 拦截弹窗（见 §15）
spctl --assess --type execute -v /tmp/OM.app                       # 期望：rejected（无公证，属预期）
xattr -dr com.apple.quarantine /tmp/OM.app && open /tmp/OM.app     # 期望：正常打开
```

---

## 13. 风险与已知坑

| # | 风险 | 影响 | 对策 / 回滚 |
|---|---|---|---|
| R1 | Swift 6 严格并发 + WebKit 代理（`WKNavigationDelegate` 等非隔离协议）编译报错 | 阻塞 | 用 Xcode 26 `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`；仍不行退回 `SWIFT_VERSION: "5"`（`[已知]` 可用） |
| R2 | `loadFileURL(allowingReadAccessTo: "/")` 在 macOS 26 WebKit 被收紧 | 图片不显示 | 切 P2 的 `WKURLSchemeHandler` 方案，接口不变 `[推测]` |
| R3 | `file://` 源下 CSP `'self'` 不匹配导致本地 vendor 脚本被拦 | 空白页 | 改用 `script-src file:`；F6 用例守住"内联脚本不执行" `[推测]` |
| R4 | SwiftUI `Window` scene 关闭后由 `application(_:open:)` 重开窗口 | 双击文件无窗口 | 在视图 `onAppear` 注入 `openWindow` 闭包；`applicationShouldHandleReopen` 返回 true；P2 改 `WindowGroup` `[推测]` |
| R5 | `List(children:)` 超大目录卡顿 | 体验 | 深度 8 / 5000 节点上限、后台建树、忽略常见大目录 |
| R6 | DispatchSource 监听在原子写后失效 | 不自动刷新 | rename/delete 后轮询重挂（§6.4），F12 用例守住 |
| R7 | macOS 15+ 移除"右键 ▸ 打开"绕过 Gatekeeper 的方式 | 他人首次打开被拦 | README 写清"系统设置 ▸ 隐私与安全性 ▸ 仍要打开"或 `xattr -dr` `[已知]` |
| R8 | 修改已签名 bundle 内文件（如手改 Renderer）会导致"已损坏" | 无法启动 | 任何修改后重跑 `build.sh` 重签 |
| R9 | macOS 26 对旧格式图标的 Liquid Glass 处理效果未知 | 视觉 | 实机看 Dock；不满意用 Icon Composer 出 `.icon` `[推测]` |
| R10 | 打印空白（`printOperation` view frame 为零） | P2 | 设 `op.view?.frame` workaround `[推测]` |
| R11 | `LSHandlerRank: Default` 与 Typora `Owner` 并存时默认打开程序仍是 Typora | 体验 | 用户在 Finder "显示简介 ▸ 打开方式 ▸ 全部更改"；或卸载 Typora 后 LaunchServices 自动切换 |
| R12 | xcodegen `type: folder` 资源与 `path: OneMarkdown` 重复收录 | 构建警告 / 重复文件 | `excludes: ["Resources/Renderer"]`；构建后 `ls Contents/Resources` 核对只有一份 |
| R13 | `NSAllowsArbitraryLoadsInWebContent` 触发 App Store 审核问题 | 不适用（不上架） | 无 |
| R14 | TCC 弹窗（Desktop/Documents/Downloads）被拒 | 打不开文件 | banner 指引 |
| R15 | KaTeX 字体 60+ 文件、mermaid 2.6 MB 让 bundle 变大 | 体积 | 都在 P2，默认不打包 |

---

## 14. 实施顺序、回滚点与并行拆分

> 每个阶段结束 `git commit`（`git init` 为第 0 步；只 `git add` 具体文件），作为回滚点。业务逻辑改动完成后按全局规则跑 `/code-review high`。

| 阶段 | 内容 | 产出 / 验收 | 依赖 |
|---|---|---|---|
| **P0 骨架**（串行） | `git init`、`.gitignore`、`project.yml`、`OneMarkdownApp/AppDelegate/AppState`、空 `MainWindowView`（NavigationSplitView + 占位）、测试 target 空用例 | `xcodegen generate && xcodebuild build` 通过，空窗口能开 | 无 |
| **P1-A 渲染层**（可并行） | `fetch-vendor.sh`、`index.html`、`app.js`、`theme.css`、`samples/` | 在 Safari 直接 `open index.html`，控制台 `OneMD.render({text:…, baseHref:'file:///…/samples/'})` 出正确 HTML；F6/F7 视觉达标 | 无（纯前端） |
| **P1-B Swift 服务层**（可并行） | `MarkdownFileTypes`、`DocumentLoader`、`FileTreeBuilder`、`RecentFilesStore`、`FileWatcher` + 对应单元测试 | `xcodebuild test` 全绿 | P0 |
| **P1-C 图标与脚本**（可并行） | `generate_app_icon.swift`、`make-icon.sh`、`build.sh`、`make-dmg.sh` | `build.sh` 出 dist/.app 且 `codesign --verify` 通过；`make-dmg.sh` 出 DMG | P0（需 project.yml） |
| **P2 集成**（串行） | `RendererBridge`、`MarkdownWebView`、`WorkspaceViewModel`、`SidebarView/FileTreeView/OutlineView`、`AppCommands`、四条打开入口、链接/图片策略、热重载、主题 | F1–F17 通过 | P1-A/B |
| **P3 完善**（串行） | 查找条、侧栏过滤、最近打开、窗口 / 缩放记忆、空状态、banner、右键菜单 | F18–F20 通过 | P2 |
| **P4 交付**（串行） | README（含 §15）、`install-local.sh`、DMG 冒烟、Gatekeeper 模拟 | §12.1 与 §12.3 全部通过 | P1-C、P3 |
| **P5 加分**（按需） | 打印 / PDF、KaTeX、多窗口、FSEvents、scheme handler、mermaid | F21 | P4 |

并行建议：P1-A（前端）、P1-B（Swift 服务 + 测试）、P1-C（脚本 / 图标）三条线互不依赖，可分给三个 coder 同时做；P2 是唯一的汇合点，由一人串行完成。reviewer 重点看：`RendererBridge` 的导航策略与消息桥（安全边界）、`FileWatcher` 的 fd 生命周期（泄漏 / 悬挂）、`DocumentLoader` 的编码与大小分支。

---

## 15. Gatekeeper 首次打开说明（可直接放 README）

OneMarkdown 使用 ad-hoc 签名，未经 Apple 公证。**在本机自己构建并安装**时没有 quarantine 标记，双击即可打开。若 DMG 经 AirDrop / 微信 / 浏览器下载等途径传到另一台 Mac，首次打开会看到：

> "OneMarkdown"未能打开，因为 Apple 无法验证其是否包含恶意软件。

处理方式任选其一（macOS 15 及以后不再支持"右键 ▸ 打开"绕过 `[已知]`）：

1. 关闭弹窗后，打开 **系统设置 ▸ 隐私与安全性**，下滑到"安全性"区域，点击 **"仍要打开"**，输入密码确认。之后不再提示。
2. 终端执行：`xattr -dr com.apple.quarantine /Applications/OneMarkdown.app`，再正常打开。

若提示 **"已损坏，无法打开"**：说明 App 内文件在签名后被修改（或下载不完整），重新拷贝 / 重新构建即可。

---

## 附录 A：Swift ↔ JS 消息协议

| 方向 | 名称 | 载荷 | 说明 |
|---|---|---|---|
| JS→Swift | `ready` | — | `DOMContentLoaded` 后发送；Swift 收到前的 render 请求排队 |
| JS→Swift | `outline` | `[{level:Int, text:String, id:String}]` | 每次渲染后 |
| JS→Swift | `rendered` | `{docId, ms}` | 计时 / 日志 |
| JS→Swift | `findResult` | `{current:Int, total:Int}` | 查找后 |
| JS→Swift | `error` | `{message}` | `window.onerror` |
| Swift→JS | `OneMD.render(p)` | `{text, baseHref, docId, preserveScroll}` | 通过 `callAsyncJavaScript` 传对象 |
| Swift→JS | `OneMD.scrollToHeading(id)` | String | — |
| Swift→JS | `OneMD.find(q, {direction:'next'|'prev'})` / `OneMD.clearFind()` | — | — |

## 附录 B：快捷键表

| 快捷键 | 动作 | 备注 |
|---|---|---|
| ⌘O | 打开文件 / 文件夹 | 同一面板 |
| ⌘⇧O | 打开文件夹 | 面板只允许目录 |
| ⌘⇧L | 显示 / 隐藏侧栏 | Typora 同键位；系统默认 ⌃⌘S 也保留 |
| ⌘1 / ⌘2 | 侧栏切到 文件树 / 大纲 | — |
| ⌘F / ⌘G / ⌘⇧G / Esc | 查找 / 下一个 / 上一个 / 关闭 | — |
| ⌘R | 重新加载当前文档 | — |
| ⌘+ / ⌘- / ⌘0 | 放大 / 缩小 / 重置 | `pageZoom` |
| ⌘P | 打印 | P2 |
| ⌘⇧R | 在 Finder 中显示 | — |
| ⌘W | 关闭窗口 | 系统默认 |

## 附录 C：`samples/demo.md` 必须覆盖的元素

一级至三级中文标题（含重复标题验证 slug 去重）、段落内 `行内代码`、`bash` 与 `curl` 与 `json` 三种围栏代码块、无语言代码块、带对齐的表格（表头加粗）、有序 / 无序 / 嵌套列表、任务列表、引用块、水平线、脚注 `[^1]`、相对图片 `images/demo.png`、上级相对图片、远程 https 图片、不存在的图片、外链、`sub/linked.md` 相对链接、`#锚点` 链接、`<details><summary>` 原始 HTML、`<script>alert(1)</script>`（验证被剔除）、一段 CRLF 换行、emoji 与全角标点。

## 附录 D：命名备选

已定 `OneMarkdown`（bundle id `com.iamxmm.onemarkdown`）。备选：`MarkView`、`MDLens`、`Mardown Reader`（若以后要上架再改，成本仅 project.yml 三处）。
