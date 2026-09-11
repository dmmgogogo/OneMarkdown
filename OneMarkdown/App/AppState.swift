import Foundation

/// 进程级共享状态：AppDelegate 收到的打开请求先排队，等主窗口视图挂载后再消费。
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    /// 待打开的 URL（Finder 双击 / Dock 拖入 / `open -a` 都会进这里）
    var pendingOpenURLs: [URL] = []
    /// 由主窗口视图注入，用于窗口被关闭后重新打开
    var openMainWindow: (() -> Void)?

    private init() {}
}
