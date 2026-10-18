import AppKit
import Foundation

/// 记住用户选定的外部编辑器。以 bundle identifier 为准，同时记下选中时的路径作回退。
@MainActor
@Observable
final class ExternalEditorStore {
    static let key = "externalEditorBundleID"
    static let pathKey = "externalEditorPath"

    private let defaults: UserDefaults
    /// 本 App 自己的 bundle id，用来拒绝“自己打开自己”；测试中可替换。
    private let selfBundleID: String?

    private(set) var bundleID: String?
    /// 选中时的路径。LaunchServices 尚未收录该 App 时靠它兜底。
    private var storedPath: String?
    /// 菜单标题用。解析一次缓存起来：菜单 body 会被频繁重算，不能每次都查 LaunchServices。
    private(set) var editorName: String?

    init(defaults: UserDefaults = .standard, selfBundleID: String? = Bundle.main.bundleIdentifier) {
        self.defaults = defaults
        self.selfBundleID = selfBundleID
        self.bundleID = defaults.string(forKey: Self.key)
        self.storedPath = defaults.string(forKey: Self.pathKey)
        self.editorName = nil
        refreshName()
    }

    /// 已选编辑器当前所在位置；没选过或已被卸载时为 nil。
    var editorURL: URL? {
        guard let bundleID else { return nil }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return url }
        // LaunchServices 还没收录（刚解压没启动过、装在外置盘或自定义目录）时按原路径找，
        // 但要确认那里还是同一个程序，免得用户把它换掉后仍然启动。
        guard let storedPath, FileManager.default.fileExists(atPath: storedPath) else { return nil }
        let url = URL(fileURLWithPath: storedPath)
        // Bundle(url:) 在进程内有缓存，这道校验挡的是“下次启动时原地已换成别的程序”
        guard Bundle(url: url)?.bundleIdentifier == bundleID else { return nil }
        return url
    }

    /// 记住一个编辑器。读不出 bundle id、或选中本 App 自己，都拒绝。
    @discardableResult
    func remember(_ appURL: URL) -> Bool {
        guard let id = Bundle(url: appURL)?.bundleIdentifier, !id.isEmpty, id != selfBundleID else { return false }
        let path = appURL.standardizedFileURL.path
        bundleID = id
        storedPath = path
        defaults.set(id, forKey: Self.key)
        defaults.set(path, forKey: Self.pathKey)
        refreshName()
        return true
    }

    /// 用户开了“显示所有文件扩展名”时 displayName 会带上 .app，菜单里不需要。
    private func refreshName() {
        guard let url = editorURL else {
            editorName = nil
            return
        }
        let name = FileManager.default.displayName(atPath: url.path)
        editorName = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
