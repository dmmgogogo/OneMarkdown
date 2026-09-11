import AppKit
import UniformTypeIdentifiers
import WebKit

/// 持有 WKWebView，负责 Swift ↔ JS 通信、导航策略、缩放与打印。
/// index.html 只加载一次，之后所有文档切换都通过 `OneMD.render(...)` 传参完成。
@MainActor
final class RendererBridge: NSObject {
    let webView: WKWebView

    /// JS 发来的消息（ready / outline / findResult / error ...）
    var onMessage: ((BridgeMessage) -> Void)?
    /// 用户点击了指向本地 Markdown 文件的链接
    var onOpenMarkdown: ((URL) -> Void)?

    private let indexURL: URL
    private let messageHandler = WeakMessageHandler()
    /// 页面脚本是否已就绪。未就绪期间的调用直接丢弃：ready 到达后由 ViewModel 以 currentDocument 为准重绘。
    private(set) var isReady = false

    static let minZoom: CGFloat = 0.6
    static let maxZoom: CGFloat = 2.0
    static let zoomStep: CGFloat = 0.1

    override init() {
        let rendererDir = Bundle.main.resourceURL!.appendingPathComponent("Renderer", isDirectory: true)
        indexURL = rendererDir.appendingPathComponent("index.html")

        let config = WKWebViewConfiguration()
        config.userContentController.add(messageHandler, name: "bridge")
        config.preferences.isFraudulentWebsiteWarningEnabled = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = ViewerWebView(frame: .zero, configuration: config)
        super.init()

        messageHandler.target = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = .textBackgroundColor
        #if DEBUG
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        #endif

        loadIndex()
    }

    private func loadIndex() {
        isReady = false
        // 放行整个文件系统的读权限，文档里的相对路径图片才能显示（沙盒未开启，进程本来就可读）
        webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/", isDirectory: true))
    }

    // MARK: - Swift → JS

    func render(text: String, baseHref: String, docId: String, preserveScroll: Bool) {
        call("OneMD.render(payload)", arguments: [
            "payload": [
                "text": text,
                "baseHref": baseHref,
                "docId": docId,
                "preserveScroll": preserveScroll,
            ] as [String: Any],
        ])
    }

    func scrollToHeading(id: String) {
        call("OneMD.scrollToHeading(id)", arguments: ["id": id])
    }

    func find(query: String, direction: String) {
        call("OneMD.find(q, dir)", arguments: ["q": query, "dir": direction])
    }

    func clearFind() {
        call("OneMD.clearFind()", arguments: [:])
    }

    var pageZoom: CGFloat {
        get { webView.pageZoom }
        set { webView.pageZoom = min(max(newValue, Self.minZoom), Self.maxZoom) }
    }

    private func call(_ body: String, arguments: [String: Any]) {
        guard isReady else { return }
        Task { @MainActor [webView] in
            do {
                if arguments.isEmpty {
                    _ = try await webView.evaluateJavaScript(body)
                } else {
                    _ = try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
                }
            } catch {
                NSLog("OneMarkdown JS call failed: %@ — %@", body, String(describing: error))
            }
        }
    }

    // MARK: - 打印 / PDF

    func print(in window: NSWindow?) {
        let info = NSPrintInfo()
        configure(printInfo: info)
        let op = webView.printOperation(with: info)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        // 已知坑：view frame 为零会打印空白
        op.view?.frame = NSRect(origin: .zero, size: info.paperSize)
        if let window {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }

    /// 分页导出 PDF（NSPrintOperation 保存到文件）。失败时回退为整页长图。
    func exportPDF(to url: URL, completion: @escaping (Error?) -> Void) {
        let info = NSPrintInfo()
        configure(printInfo: info)
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let op = webView.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.view?.frame = NSRect(origin: .zero, size: info.paperSize)
        let ok = op.run()
        if ok, FileManager.default.fileExists(atPath: url.path) {
            completion(nil)
            return
        }
        // 回退：单页长图
        webView.createPDF { result in
            switch result {
            case .success(let data):
                do { try data.write(to: url); completion(nil) } catch { completion(error) }
            case .failure(let error):
                completion(error)
            }
        }
    }

    private func configure(printInfo info: NSPrintInfo) {
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
    }

    // MARK: - 链接策略

    /// 本地文件链接：只有“文档类”文件才交给默认程序打开，其余（可执行文件、脚本、应用、目录、未知类型）一律只在 Finder 中显示。
    private static func isSafeToOpenExternally(_ url: URL) -> Bool {
        let ext = url.pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        let denied: [UTType] = [.executable, .script, .shellScript, .application, .applicationBundle, .package, .diskImage, .systemPreferencesPane]
        if denied.contains(where: { type.conforms(to: $0) }) { return false }
        let allowed: [UTType] = [.image, .pdf, .text, .audiovisualContent, .archive, .spreadsheet, .presentation, .rtfd]
        return allowed.contains(where: { type.conforms(to: $0) })
    }

    private func handleLinkActivation(_ url: URL) {
        switch url.scheme?.lowercased() {
        case "http", "https", "mailto":
            NSWorkspace.shared.open(url)
        case "file":
            // 空 href / 指向渲染页自身的链接：忽略
            if url.path == indexURL.path { return }
            let path = url.path
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return }
            if !isDir.boolValue && MarkdownFileTypes.isMarkdown(url) {
                onOpenMarkdown?(url)
            } else if !isDir.boolValue && Self.isSafeToOpenExternally(url) {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        default:
            break
        }
    }
}

/// 去掉右键菜单里的“重新载入 / 后退 / 前进 / 新窗口打开 / 下载”等对只读查看器无意义（且会绕过导航策略）的项。
private final class ViewerWebView: WKWebView {
    private static let removedIdentifierFragments = ["Reload", "GoBack", "GoForward", "InNewWindow", "Download"]

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items {
            let id = item.identifier?.rawValue ?? ""
            if Self.removedIdentifierFragments.contains(where: { id.contains($0) }) {
                menu.removeItem(item)
            }
        }
        // 清理因删除产生的连续 / 首尾分隔线
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem {
                if previousWasSeparator { menu.removeItem(item) } else { previousWasSeparator = true }
            } else {
                previousWasSeparator = false
            }
        }
        if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
    }
}

// MARK: - WKNavigationDelegate

extension RendererBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if navigationAction.navigationType == .linkActivated {
            handleLinkActivation(url)
            return .cancel
        }
        // 只允许加载自己的 index.html（含 #anchor）
        if url.isFileURL, url.path == indexURL.path { return .allow }
        return .cancel
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // 任何整页导航（首次加载 / 重新载入）开始后，脚本环境都会重建，此前的桥接调用不再有效
        isReady = false
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("OneMarkdown: web content process terminated, reloading")
        loadIndex()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        reportLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        reportLoadFailure(error)
    }

    private func reportLoadFailure(_ error: any Error) {
        let nsError = error as NSError
        // 用户触发的取消（如快速连续导航）不算错误
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        onMessage?(.error("渲染页面加载失败：\(error.localizedDescription)"))
    }
}

// MARK: - WKUIDelegate

extension RendererBridge: WKUIDelegate {
    // 阻止 target=_blank 等弹出新窗口，改为按链接策略处理
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { handleLinkActivation(url) }
        return nil
    }
}

// MARK: - JS → Swift

extension RendererBridge {
    fileprivate func receive(_ body: Any) {
        guard let message = BridgeMessage(body: body) else { return }
        if case .ready = message { isReady = true }
        onMessage?(message)
    }
}

/// 弱引用代理，避免 WKUserContentController ↔ bridge 循环引用。
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: RendererBridge?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.receive(message.body)
    }
}
