import Foundation

/// 侧栏文件树节点。`children == nil` 表示文件，非 nil 表示目录。
nonisolated struct FileNode: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?

    var id: URL { url }

    init(url: URL, isDirectory: Bool, children: [FileNode]? = nil) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.children = isDirectory ? (children ?? []) : nil
    }

    /// 递归统计文件数（不含目录）。
    var fileCount: Int {
        guard let children else { return 1 }
        return children.reduce(0) { $0 + $1.fileCount }
    }

    /// 深度优先返回树中所有文件节点。
    var allFiles: [FileNode] {
        guard let children else { return [self] }
        return children.flatMap(\.allFiles)
    }
}
