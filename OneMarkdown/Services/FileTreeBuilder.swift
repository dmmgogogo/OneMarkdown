import Foundation

/// 把目录枚举成 FileNode 树：只保留 Markdown 文件与含 Markdown 的目录。
nonisolated enum FileTreeBuilder {
    struct Limits: Sendable {
        var maxDepth = 8
        var maxNodes = 5000
        static let `default` = Limits()
    }

    struct Result: Sendable {
        let root: FileNode
        /// 是否因文件数超过 maxNodes 而截断（层级过深被跳过不算，那是正常的静默剪枝）。
        let truncated: Bool
        /// 根目录本身无法枚举（不存在 / 无权限）时的错误描述。
        let rootError: String?
    }

    static func build(root: URL, limits: Limits = .default) -> Result {
        var budget = limits.maxNodes
        var truncated = false
        // 根目录先单独试读一次，把 TCC 拒绝等错误暴露出来，而不是静默显示“没有文件”
        if let error = probe(root) {
            return Result(root: FileNode(url: root, isDirectory: true, children: []), truncated: false, rootError: error)
        }
        // 已访问的真实路径，防止符号链接成环
        var visited: Set<String> = [root.resolvingSymlinksInPath().path]
        let node = buildDirectory(root, depth: 0, limits: limits, budget: &budget, truncated: &truncated, visited: &visited)
        return Result(root: node ?? FileNode(url: root, isDirectory: true, children: []), truncated: truncated, rootError: nil)
    }

    /// 只列出一层：非隐藏、非忽略的目录（不判断里面有没有 Markdown）+ Markdown 文件，目录在前、Finder 顺序。
    /// 侧栏按需展开时用，避免打开一个文件就递归扫描整棵目录树。
    static func listDirectory(_ url: URL) throws -> [FileNode] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isHiddenKey]
        let names = try fm.contentsOfDirectory(atPath: url.path)
        var dirs: [FileNode] = []
        var files: [FileNode] = []
        for name in names {
            if name.hasPrefix(".") { continue }
            let entry = url.appendingPathComponent(name)
            let values = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isHidden == true || values?.isPackage == true { continue }
            var isDir = values?.isDirectory ?? false
            if values?.isSymbolicLink == true {
                var targetIsDir: ObjCBool = false
                guard fm.fileExists(atPath: entry.resolvingSymlinksInPath().path, isDirectory: &targetIsDir) else { continue }
                isDir = targetIsDir.boolValue
            }
            if isDir {
                if MarkdownFileTypes.ignoredDirectoryNames.contains(name) { continue }
                dirs.append(FileNode(url: entry, isDirectory: true, children: []))
            } else if MarkdownFileTypes.isMarkdown(entry) {
                files.append(FileNode(url: entry, isDirectory: false))
            }
        }
        dirs.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return dirs + files
    }

    /// 把枚举错误翻译成用户可读的提示。
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError {
            return "没有读取该文件夹的权限，请在“系统设置 › 隐私与安全性 › 文件和文件夹”中允许 OneMarkdown"
        }
        return error.localizedDescription
    }

    private static func probe(_ url: URL) -> String? {
        do {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
            return nil
        } catch {
            return describe(error)
        }
    }

    /// 返回 nil 表示该目录下没有任何 Markdown（会被剪掉）。根目录例外，由调用方兜底。
    private static func buildDirectory(
        _ url: URL, depth: Int, limits: Limits,
        budget: inout Int, truncated: inout Bool, visited: inout Set<String>
    ) -> FileNode? {
        // 超过最大层级静默跳过：Downloads 之类的目录里嵌套很深的工程很常见，不值得每次都警告
        guard depth <= limits.maxDepth else { return nil }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isHiddenKey]
        // 用路径版 API：URL 版 contentsOfDirectory(at:) 不会跟随指向目录的符号链接（直接报“无法打开”）
        guard let names = try? fm.contentsOfDirectory(atPath: url.path) else {
            return nil
        }

        var dirs: [FileNode] = []
        var files: [FileNode] = []
        for name in names.sorted() {
            if budget <= 0 { truncated = true; break }
            if name.hasPrefix(".") { continue }
            let entry = url.appendingPathComponent(name)
            let values = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isHidden == true || values?.isPackage == true { continue }
            let isSymlink = values?.isSymbolicLink ?? false
            var isDir = values?.isDirectory ?? false
            if isSymlink {
                // isDirectoryKey 不解析符号链接，这里按目标判断；目标不存在的悬空链接直接跳过
                var targetIsDir: ObjCBool = false
                guard fm.fileExists(atPath: entry.resolvingSymlinksInPath().path, isDirectory: &targetIsDir) else { continue }
                isDir = targetIsDir.boolValue
            }

            if isDir {
                if MarkdownFileTypes.ignoredDirectoryNames.contains(name) { continue }
                // 符号链接目录按真实路径去重，防止成环；未访问过的正常递归
                let real = entry.resolvingSymlinksInPath().path
                if visited.contains(real) { continue }
                visited.insert(real)
                if let child = buildDirectory(entry, depth: depth + 1, limits: limits, budget: &budget, truncated: &truncated, visited: &visited) {
                    budget -= 1
                    dirs.append(child)
                }
            } else if MarkdownFileTypes.isMarkdown(entry) {
                budget -= 1
                files.append(FileNode(url: entry, isDirectory: false))
            }
        }

        if dirs.isEmpty && files.isEmpty { return nil }
        let sortedDirs = dirs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let sortedFiles = files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return FileNode(url: url, isDirectory: true, children: sortedDirs + sortedFiles)
    }

    /// 按文件名过滤，返回匹配的文件（扁平列表，用于搜索模式）。
    static func filter(_ root: FileNode, query: String) -> [FileNode] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return root.allFiles.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
}
