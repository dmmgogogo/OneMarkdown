import AppKit
import Foundation

/// 最近打开的文件列表（UserDefaults 持久化，去重，最多 `limit` 条）。
@MainActor
@Observable
final class RecentFilesStore {
    static let key = "recentFiles"
    let limit: Int
    private let defaults: UserDefaults
    /// 是否同步到 NSDocumentController（Dock 右键菜单）。单元测试跑在真实 App 宿主里，必须关掉以免污染用户的最近项目。
    private let syncsWithSystem: Bool

    private(set) var urls: [URL] = []

    init(defaults: UserDefaults = .standard, limit: Int = 10, syncsWithSystem: Bool = true) {
        self.defaults = defaults
        self.limit = limit
        self.syncsWithSystem = syncsWithSystem
        self.urls = (defaults.stringArray(forKey: Self.key) ?? []).map { URL(fileURLWithPath: $0) }
    }

    func add(_ url: URL) {
        let standardized = url.standardizedFileURL
        urls.removeAll { $0.standardizedFileURL == standardized }
        urls.insert(standardized, at: 0)
        if urls.count > limit { urls = Array(urls.prefix(limit)) }
        persist()
        // 同步给系统，让 Dock 右键菜单也能看到
        if syncsWithSystem { NSDocumentController.shared.noteNewRecentDocumentURL(standardized) }
    }

    func clear() {
        urls = []
        persist()
        if syncsWithSystem { NSDocumentController.shared.clearRecentDocuments(nil) }
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func persist() {
        defaults.set(urls.map(\.path), forKey: Self.key)
    }
}
