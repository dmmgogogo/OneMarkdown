# OneMarkdown

macOS 原生的 **只读 Markdown 查看器**，替代 Typora 的「看文档」场景：GitHub 风格渲染、代码高亮、表格、任务列表、脚注、侧栏文件树与大纲、文件变更自动刷新、明暗跟随系统。不做编辑。

- 系统要求：macOS 14.0+，Apple Silicon（可用 `--universal` 出 Intel 兼容版）
- 技术栈：SwiftUI + AppKit 壳，`WKWebView` + markdown-it / highlight.js / DOMPurify 本地渲染，运行时不联网
- 正文字体：Open Sans（随 App 打包，OFL 许可）+ 系统苹方；代码字体：Consolas / Courier 系

## 功能

| 功能 | 入口 |
|---|---|
| 打开文件 / 文件夹 | ⌘O、⌘⇧O、Finder 双击、拖到窗口或 Dock、`open -a OneMarkdown xxx.md` |
| 侧栏：文件树 / 大纲 | ⌘1 / ⌘2；⌘⇧L 显示 / 隐藏侧栏 |
| 文件名过滤 | 侧栏搜索框 |
| 正文查找 | ⌘F，⌘G / ⌘⇧G 上下一个，Esc 关闭 |
| 重新加载 | ⌘R（文件被外部修改时会自动刷新，含 vim / VS Code 的原子替换写入） |
| 缩放 | ⌘+ / ⌘- / ⌘0 |
| 链接 | 外链走系统浏览器；相对 `.md` 链接 App 内打开；`#锚点` 页内跳转 |
| 最近打开 | 文件 › 最近打开 |
| 打印 / 导出 PDF | ⌘P / 文件 › 导出为 PDF… |
| 在 Finder 中显示 | ⌘⇧R |
| 重命名 / 移到废纸篓 | 侧栏右键，或 文件 › 重命名… / 移到废纸篓（⌘⌫） |

## 构建与安装

```bash
scripts/fetch-vendor.sh      # 下载渲染层依赖（首次；已提交进仓库，离线可跳过）
scripts/make-icon.sh         # 生成图标（已提交，可跳过）
scripts/build.sh --test      # 单元测试 + Release 构建 + ad-hoc 签名 → dist/OneMarkdown.app
scripts/make-dmg.sh          # 打包 → dist/OneMarkdown-<version>.dmg
scripts/install-local.sh     # 安装到 /Applications
```

需要 Xcode 26+ 与 [xcodegen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。全流程纯命令行，不需要打开 Xcode。

## 首次打开被 Gatekeeper 拦截

OneMarkdown 使用 ad-hoc 签名，未经 Apple 公证。**在本机自己构建并安装**时没有 quarantine 标记，双击即可打开。若 DMG 经 AirDrop / 微信 / 浏览器下载等途径传到另一台 Mac，首次打开会看到：

> "OneMarkdown"未能打开，因为 Apple 无法验证其是否包含恶意软件。

处理方式任选其一（macOS 15 及以后不再支持「右键 › 打开」绕过）：

1. 关闭弹窗后，打开 **系统设置 › 隐私与安全性**，下滑到「安全性」区域，点击 **「仍要打开」**，输入密码确认。之后不再提示。
2. 终端执行：

   ```bash
   xattr -dr com.apple.quarantine /Applications/OneMarkdown.app
   ```

若提示 **「已损坏，无法打开」**：说明 App 内文件在签名后被修改（或下载不完整），重新拷贝 / 重新构建即可。

## 设为 .md 默认打开程序

OneMarkdown 注册为 Markdown 的「可选」打开程序（不主动抢默认，避免和 Typora 打架）。要设为默认：Finder 中选中任一 `.md` › **显示简介** › **打开方式** 选 OneMarkdown › **全部更改…**。

## 目录结构

```
OneMarkdown/
├── App/            App 入口、AppDelegate、菜单命令、全局状态
├── Models/         FileNode / OutlineItem / MarkdownDocument / BridgeMessage
├── Services/       DocumentLoader（编码回退、大小与二进制探测）、FileTreeBuilder、FileWatcher、RecentFilesStore
├── ViewModels/     WorkspaceViewModel（根目录、当前文档、大纲、查找、监听编排）
├── Rendering/      RendererBridge（WKWebView、Swift↔JS 桥、导航策略、打印）
├── Views/          主窗口、侧栏、内容区、查找条、提示条
└── Resources/Renderer/   index.html + app.js + theme.css + vendor/（markdown-it、hljs、DOMPurify、Open Sans）
OneMarkdownTests/   单元测试（xcodebuild test）
scripts/            fetch-vendor / make-icon / build / make-dmg / install-local
samples/            验收用样例文档
docs/PLAN.md        实施方案
```

## 安全边界

- Markdown 里的原始 HTML 会经过 DOMPurify：`<script>`、`<iframe>`、事件属性、`javascript:` 一律剔除
- 页面 CSP 禁止脚本联网、iframe、表单；只允许加载本地脚本与图片（远程图片允许 `https/http`）
- 文件 > 20 MB 拒绝打开，含 NUL 字节的二进制拒绝；UTF-8 失败后按 GB18030 / Big5 / Shift-JIS 探测
- 不开 App Sandbox（否则双击打开的文档读不到同目录图片），WebContent 进程仍由 WebKit 自身沙盒保护

## 许可证

本项目代码 MIT。第三方组件许可见 `OneMarkdown/Resources/Renderer/vendor/LICENSES/`。
