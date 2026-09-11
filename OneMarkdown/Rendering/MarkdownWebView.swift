import SwiftUI
import WebKit

/// 把 bridge 持有的 WKWebView 放进 SwiftUI 视图树。
struct MarkdownWebView: NSViewRepresentable {
    let bridge: RendererBridge

    func makeNSView(context: Context) -> WKWebView {
        bridge.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
