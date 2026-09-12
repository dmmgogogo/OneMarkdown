import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 工作区核心编排：根目录、当前文档、文件树、大纲、查找、监听。
@MainActor
@Observable
final class WorkspaceViewModel {
    enum SidebarMode: String, CaseIterable {
        case files, outline
    }

    struct Banner: Identifiable, Equatable {
        enum Kind { case info, warning, error }
        let id = UUID()
        let kind: Kind
        let message: String
    }

    enum PrefKey {
        static let sidebarVisible = "sidebarVisible"
        static let pageZoom = "pageZoom"
        static let sidebarMode = "sidebarMode"
    }

    // MARK: - 状态

    private(set) var rootFolder: URL?
    /// 已读取的目录内容（按层懒加载），键为 standardizedFileURL
    private(set) var directoryContents: [URL: [FileNode]] = [:]
    private(set) var loadingDirectories: Set<URL> = []
    /// 侧栏里展开的目录
    private(set) var expandedDirectories: Set<URL> = []
    /// 搜索结果（文件名过滤，需要全目录扫描，只在输入时触发）
    private(set) var searchResults: [FileNode] = []
    private(set) var isSearching = false
    private(set) var currentDocument: MarkdownDocument?
    private(set) var outline: [OutlineItem] = []
    var selectedNodeID: URL?
    var selectedOutlineID: String?
    var banner: Banner?
    var filterText = "" {
        didSet { if filterText != oldValue { runSearch() } }
    }

    /// 右键“重命名…”弹窗的目标与输入框内容
    var renameTarget: URL?
    var renameText = ""
    /// 右键“移到废纸篓”确认弹窗的目标
    var trashTarget: URL?

    var sidebarMode: SidebarMode {
        didSet { UserDefaults.standard.set(sidebarMode.rawValue, forKey: PrefKey.sidebarMode) }
    }

    var isSidebarVisible: Bool {
        didSet { UserDefaults.standard.set(isSidebarVisible, forKey: PrefKey.sidebarVisible) }
    }

    // 查找
    var isFindVisible = false
    var findQuery = "" {
        // 查找条关闭后 TextField 可能回写旧值，这时不再触发查找
        didSet { if isFindVisible, findQuery != oldValue { runFind(direction: "next") } }
    }
    private(set) var findCurrent = 0
    private(set) var findTotal = 0

    let bridge = RendererBridge()
    let recents = RecentFilesStore()

    private var fileWatcher: FileWatcher?
    /// 根目录与已展开目录各挂一个监听，目录内容变化时只重读那一层
    private var directoryWatchers: [URL: FileWatcher] = [:]
    private var loadGeneration = 0
    private var directoryGenerations: [URL: Int] = [:]
    private var searchGeneration = 0
    /// 搜索用的全目录索引，按根目录缓存；目录有变化时失效
    private var searchIndex: (root: URL, tree: FileNode, truncated: Bool)?
    private var bannerDismissTask: Task<Void, Never>?

    // MARK: - 派生

    var documentTitle: String { currentDocument?.title ?? "OneMarkdown" }
    var documentSubtitle: String { currentDocument?.directoryURL.lastPathComponent ?? "" }
    var hasDocument: Bool { currentDocument != nil }

    /// 根目录这一层的内容；nil 表示还没读到
    var rootChildren: [FileNode]? {
        guard let rootFolder else { return nil }
        return directoryContents[Self.key(rootFolder)]
    }

    var isLoadingRoot: Bool {
        guard let rootFolder else { return false }
        return rootChildren == nil && loadingDirectories.contains(Self.key(rootFolder))
    }

    func children(of directory: URL) -> [FileNode]? {
        directoryContents[Self.key(directory)]
    }

    func isExpanded(_ directory: URL) -> Bool {
        expandedDirectories.contains(Self.key(directory))
    }

    private static func key(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    func relativePath(of url: URL) -> String {
        guard let rootFolder else { return url.path }
        let rootPath = rootFolder.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(rootPath + "/") { return String(path.dropFirst(rootPath.count + 1)) }
        return url.lastPathComponent
    }

    // MARK: - 初始化

    init() {
        let defaults = UserDefaults.standard
        sidebarMode = SidebarMode(rawValue: defaults.string(forKey: PrefKey.sidebarMode) ?? "") ?? .files
        isSidebarVisible = defaults.object(forKey: PrefKey.sidebarVisible) as? Bool ?? true
        let zoom = defaults.double(forKey: PrefKey.pageZoom)
        if zoom > 0 { bridge.pageZoom = zoom }

        bridge.onMessage = { [weak self] message in self?.handle(message) }
        bridge.onOpenMarkdown = { [weak self] url in self?.open(url) }
    }

    // MARK: - 打开

    /// 打开文件或目录。`force` 为 true 时扩展名不是 Markdown 也按文本渲染（⌘O 面板明确选择的情况）。
    func open(_ url: URL, force: Bool = false) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            show(.error, "文件不存在：\(url.path)")
            return
        }
        if isDir.boolValue {
            openFolder(url)
            return
        }
        guard force || MarkdownFileTypes.isMarkdown(url) else {
            show(.warning, "“\(url.lastPathComponent)”不是 Markdown 文件")
            return
        }
        loadDocument(url, preserveScroll: false)
        // 文件不在当前根目录下时，把根目录切到它的父目录（Typora 行为）；只读这一层，不递归
        let parent = url.deletingLastPathComponent()
        if let rootFolder, url.standardizedFileURL.path.hasPrefix(rootFolder.standardizedFileURL.path + "/") {
            selectedNodeID = url
            revealInTree(url)
        } else {
            openFolder(parent, selecting: url)
        }
    }

    func openFolder(_ url: URL, selecting: URL? = nil) {
        if rootFolder.map(Self.key) != Self.key(url) {
            // 换根目录：清掉旧目录缓存、展开状态和监听
            directoryContents = [:]
            expandedDirectories = []
            loadingDirectories = []
            directoryGenerations = [:]
            searchIndex = nil
            directoryWatchers.values.forEach { $0.stop() }
            directoryWatchers = [:]
        }
        rootFolder = url
        selectedNodeID = selecting
        filterText = ""
        watchDirectory(url)
        loadDirectory(url)
        if let selecting { revealInTree(selecting) }
    }

    func openAll(_ urls: [URL]) {
        // 多个文件：只打开第一个 Markdown / 目录
        if let first = urls.first(where: { MarkdownFileTypes.isMarkdown($0) }) ?? urls.first {
            open(first)
        }
    }

    func reload(preserveScroll: Bool = true) {
        guard let doc = currentDocument else { return }
        loadDocument(doc.url, preserveScroll: preserveScroll)
    }

    func select(nodeID: URL?) {
        guard let nodeID else { return }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: nodeID.path, isDirectory: &isDir), !isDir.boolValue {
            if currentDocument?.url != nodeID { loadDocument(nodeID, preserveScroll: false) }
        }
    }

    func scrollTo(_ item: OutlineItem) {
        bridge.scrollToHeading(id: item.id)
    }

    // MARK: - 文件树（按层懒加载）

    /// 读取某个目录这一层的内容。已有缓存且 `force == false` 时不重复读。
    func loadDirectory(_ directory: URL, force: Bool = false) {
        let key = Self.key(directory)
        if !force, directoryContents[key] != nil || loadingDirectories.contains(key) { return }
        let gen = (directoryGenerations[key] ?? 0) + 1
        directoryGenerations[key] = gen
        loadingDirectories.insert(key)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try FileTreeBuilder.listDirectory(key) }
            }.value
            guard directoryGenerations[key] == gen else { return }
            loadingDirectories.remove(key)
            switch result {
            case .success(let nodes):
                directoryContents[key] = nodes
            case .failure(let error):
                directoryContents[key] = []
                show(.error, "无法读取“\(directory.lastPathComponent)”：\(FileTreeBuilder.describe(error))")
            }
        }
    }

    func setExpanded(_ directory: URL, _ expanded: Bool) {
        let key = Self.key(directory)
        if expanded {
            expandedDirectories.insert(key)
            loadDirectory(key)
            watchDirectory(key)
        } else {
            expandedDirectories.remove(key)
            directoryWatchers.removeValue(forKey: key)?.stop()
        }
    }

    /// 重新读取根目录和所有已展开目录这几层（刷新按钮、重命名/删除之后）。
    func refreshTree() {
        guard let rootFolder else { return }
        searchIndex = nil
        loadDirectory(rootFolder, force: true)
        for dir in expandedDirectories { loadDirectory(dir, force: true) }
        if !filterText.isEmpty { runSearch() }
    }

    /// 展开从根目录到 `url` 之间的所有祖先目录，让它在侧栏里可见。
    private func revealInTree(_ url: URL) {
        guard let rootFolder else { return }
        let rootPath = Self.key(rootFolder).path
        var dir = Self.key(url).deletingLastPathComponent()
        var ancestors: [URL] = []
        while dir.path.hasPrefix(rootPath + "/") {
            ancestors.append(dir)
            dir = dir.deletingLastPathComponent()
        }
        for ancestor in ancestors { setExpanded(ancestor, true) }
    }

    // MARK: - 搜索（需要全目录扫描，只在输入时做一次并缓存）

    private func runSearch() {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let root = rootFolder, !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        if let index = searchIndex, index.root == Self.key(root) {
            searchResults = FileTreeBuilder.filter(index.tree, query: query)
            return
        }
        searchGeneration += 1
        let gen = searchGeneration
        isSearching = true
        let rootKey = Self.key(root)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FileTreeBuilder.build(root: rootKey)
            }.value
            guard gen == searchGeneration else { return }
            isSearching = false
            searchIndex = (rootKey, result.root, result.truncated)
            if let rootError = result.rootError {
                show(.error, "无法读取“\(root.lastPathComponent)”：\(rootError)")
            } else if result.truncated {
                show(.info, "目录里的 Markdown 文件超过 \(FileTreeBuilder.Limits.default.maxNodes) 个，搜索只覆盖前 \(FileTreeBuilder.Limits.default.maxNodes) 个")
            }
            searchResults = FileTreeBuilder.filter(result.root, query: filterText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - 面板

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [MarkdownFileTypes.markdownUTType, .plainText, .folder]
        panel.allowsOtherFileTypes = true
        panel.message = "选择 Markdown 文件或文件夹"
        panel.directoryURL = rootFolder
        if panel.runModal() == .OK, let url = panel.url {
            open(url, force: true)
        }
    }

    func showOpenFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择要浏览的文件夹"
        panel.directoryURL = rootFolder
        if panel.runModal() == .OK, let url = panel.url {
            openFolder(url)
        }
    }

    func revealInFinder(_ url: URL? = nil) {
        if let target = url ?? currentDocument?.url ?? rootFolder {
            NSWorkspace.shared.activateFileViewerSelecting([target])
        }
    }

    func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    // MARK: - 文件操作（重命名 / 移到废纸篓）

    /// 菜单栏“重命名 / 移到废纸篓”作用的对象：侧栏选中项优先，否则当前文档。
    var fileOperationTarget: URL? {
        if let selected = selectedNodeID, FileManager.default.fileExists(atPath: selected.path) { return selected }
        return currentDocument?.url
    }

    func beginRename(_ url: URL) {
        renameText = url.lastPathComponent
        renameTarget = url
    }

    func cancelRename() {
        renameTarget = nil
        renameText = ""
    }

    /// 弹窗确认后执行重命名。失败以 banner 提示，不抛出。
    func commitRename() {
        guard let source = renameTarget else { return }
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelRename()
        guard !newName.isEmpty, newName != source.lastPathComponent else { return }
        guard !newName.contains("/"), !newName.contains(":"), newName != ".", newName != ".." else {
            show(.error, "名称不能包含“/”或“:”")
            return
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(newName)
        let fm = FileManager.default
        // 大小写不敏感的卷上，仅改大小写时 fileExists 会对自身返回 true，要放行
        let onlyCaseChanged = destination.path.lowercased() == source.path.lowercased()
        if !onlyCaseChanged, fm.fileExists(atPath: destination.path) {
            show(.error, "“\(newName)”已存在")
            return
        }
        do {
            try fm.moveItem(at: source, to: destination)
        } catch {
            show(.error, "重命名失败：\(error.localizedDescription)")
            return
        }
        // 当前文档就是被改名的文件、或位于被改名的目录下：切到新路径继续显示
        if let doc = currentDocument, let relocated = Self.relocate(doc.url, from: source, to: destination) {
            loadDocument(relocated, preserveScroll: true)
            selectedNodeID = relocated
        } else if selectedNodeID == source {
            selectedNodeID = destination
        }
        refreshTree()
    }

    func beginTrash(_ url: URL) {
        trashTarget = url
    }

    func cancelTrash() {
        trashTarget = nil
    }

    /// 弹窗确认后移到废纸篓。
    func commitTrash() {
        guard let target = trashTarget else { return }
        cancelTrash()
        do {
            try FileManager.default.trashItem(at: target, resultingItemURL: nil)
        } catch {
            show(.error, "移到废纸篓失败：\(error.localizedDescription)")
            return
        }
        if let doc = currentDocument, Self.isInside(doc.url, of: target) {
            closeDocument()
        }
        if let selected = selectedNodeID, Self.isInside(selected, of: target) {
            selectedNodeID = nil
        }
        show(.info, "已将“\(target.lastPathComponent)”移到废纸篓")
        refreshTree()
    }

    /// 关闭当前文档，回到空状态（文件被本 App 删除时使用）。
    func closeDocument() {
        fileWatcher?.stop()
        fileWatcher = nil
        currentDocument = nil
        outline = []
        selectedOutlineID = nil
        if isFindVisible { closeFind() }
    }

    /// `url` 等于 `base` 或位于其下。
    private static func isInside(_ url: URL, of base: URL) -> Bool {
        relocate(url, from: base, to: base) != nil
    }

    /// 若 `url` 等于 `oldBase` 或位于其下，返回把前缀替换为 `newBase` 后的路径；否则返回 nil。
    private static func relocate(_ url: URL, from oldBase: URL, to newBase: URL) -> URL? {
        let path = url.standardizedFileURL.path
        let oldPath = oldBase.standardizedFileURL.path
        if path == oldPath { return newBase }
        guard path.hasPrefix(oldPath + "/") else { return nil }
        let rest = String(path.dropFirst(oldPath.count + 1))
        return newBase.appendingPathComponent(rest)
    }

    // MARK: - 缩放

    func zoomIn() { setZoom(bridge.pageZoom + RendererBridge.zoomStep) }
    func zoomOut() { setZoom(bridge.pageZoom - RendererBridge.zoomStep) }
    func zoomReset() { setZoom(1.0) }

    private func setZoom(_ value: CGFloat) {
        bridge.pageZoom = (value * 10).rounded() / 10
        UserDefaults.standard.set(Double(bridge.pageZoom), forKey: PrefKey.pageZoom)
    }

    // MARK: - 查找

    func toggleFind() {
        guard hasDocument else { return }
        isFindVisible = true
        if !findQuery.isEmpty { runFind(direction: "next") }
    }

    func closeFind() {
        isFindVisible = false
        findQuery = ""
        findCurrent = 0
        findTotal = 0
        bridge.clearFind()
    }

    func findNext() { runFind(direction: "next") }
    func findPrevious() { runFind(direction: "prev") }

    private func runFind(direction: String) {
        guard hasDocument, isFindVisible else { return }
        if findQuery.isEmpty {
            findCurrent = 0
            findTotal = 0
            bridge.clearFind()
        } else {
            bridge.find(query: findQuery, direction: direction)
        }
    }

    // MARK: - 打印 / 导出

    func printDocument() {
        guard hasDocument else { return }
        bridge.print(in: NSApp.keyWindow)
    }

    func exportPDF() {
        guard let doc = currentDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = doc.title + ".pdf"
        panel.directoryURL = doc.directoryURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        bridge.exportPDF(to: url) { [weak self] error in
            if let error {
                self?.show(.error, "导出 PDF 失败：\(error.localizedDescription)")
            } else {
                self?.show(.info, "已导出：\(url.lastPathComponent)")
            }
        }
    }

    // MARK: - 提示条

    func show(_ kind: Banner.Kind, _ message: String) {
        banner = Banner(kind: kind, message: message)
        bannerDismissTask?.cancel()
        if kind != .error {
            bannerDismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                self?.banner = nil
            }
        }
    }

    func dismissBanner() {
        bannerDismissTask?.cancel()
        banner = nil
    }

    // MARK: - 内部：加载与渲染

    private func loadDocument(_ url: URL, preserveScroll: Bool) {
        loadGeneration += 1
        let gen = loadGeneration
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try DocumentLoader.load(url) }
            }.value
            guard gen == loadGeneration else { return }
            switch result {
            case .success(let doc):
                apply(doc, preserveScroll: preserveScroll)
            case .failure(let error):
                show(.error, "无法打开“\(url.lastPathComponent)”：\(error.localizedDescription)")
            }
        }
    }

    private func apply(_ doc: MarkdownDocument, preserveScroll: Bool) {
        let isSameFile = currentDocument?.resolvedURL == doc.resolvedURL
        currentDocument = doc
        if !isSameFile {
            outline = []
            selectedOutlineID = nil
            if isFindVisible { closeFind() }
            recents.add(doc.url)
        }
        if !isSameFile || banner?.kind == .error { banner = nil }
        if !doc.isUTF8 {
            show(.info, "以 \(doc.encodingName) 解码\(doc.isLossy ? "（部分字符可能丢失）" : "")")
        } else if doc.byteCount > DocumentLoader.largeWarningBytes {
            show(.info, "文件较大，渲染可能需要几秒")
        }
        bridge.render(
            text: doc.text,
            baseHref: doc.directoryURL.standardizedFileURL.absoluteString,
            docId: doc.resolvedURL.path,
            preserveScroll: preserveScroll && isSameFile
        )
        watchFile(doc.resolvedURL)
    }

    private func handle(_ message: BridgeMessage) {
        switch message {
        case .ready:
            // 页面每次就绪（首次加载 / 右键重新载入 / WebContent 进程重启）都以 currentDocument 为准重绘一次；
            // 页面未就绪期间 bridge 会丢弃调用，所以这里是唯一的补渲染点
            if let doc = currentDocument {
                bridge.render(text: doc.text, baseHref: doc.directoryURL.standardizedFileURL.absoluteString,
                              docId: doc.resolvedURL.path, preserveScroll: false)
            }
        case .outline(let items):
            outline = items
        case .rendered:
            break
        case .findResult(let current, let total):
            findCurrent = current
            findTotal = total
        case .error(let message):
            show(.error, message)
        }
    }

    // MARK: - 内部：监听

    private func watchFile(_ url: URL) {
        if fileWatcher?.url == url { return }
        fileWatcher?.stop()
        fileWatcher = FileWatcher(url: url, isDirectory: false) { [weak self] event in
            guard let self else { return }
            switch event {
            case .modified, .recreated:
                if banner?.kind == .warning { banner = nil }
                reload(preserveScroll: true)
            case .removed:
                show(.warning, "文件已被删除或移动，显示的是最后一次内容")
            }
        }
        fileWatcher?.start()
    }

    private func watchDirectory(_ url: URL) {
        let key = Self.key(url)
        if directoryWatchers[key] != nil { return }
        let watcher = FileWatcher(url: key, isDirectory: true, debounce: .milliseconds(300)) { [weak self] event in
            guard let self else { return }
            searchIndex = nil
            switch event {
            case .modified, .recreated:
                loadDirectory(key, force: true)
                if !filterText.isEmpty { runSearch() }
            case .removed:
                if key == rootFolder.map(Self.key) {
                    directoryContents = [:]
                    show(.warning, "文件夹已被删除或移动")
                } else {
                    directoryContents.removeValue(forKey: key)
                    expandedDirectories.remove(key)
                    directoryWatchers.removeValue(forKey: key)?.stop()
                    if let parent = Optional(key.deletingLastPathComponent()) { loadDirectory(parent, force: true) }
                }
            }
        }
        watcher.start()
        directoryWatchers[key] = watcher
    }
}
