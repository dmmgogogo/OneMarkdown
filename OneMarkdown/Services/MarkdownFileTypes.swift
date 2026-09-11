import Foundation
import UniformTypeIdentifiers

/// Markdown 文件类型判定与常量。
nonisolated enum MarkdownFileTypes {
    /// 与 Info.plist 中 CFBundleDocumentTypes 注册的扩展名保持一致。
    static let extensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext", "rmd", "qmd", "mdx",
    ]

    /// 文件树枚举时直接跳过的目录名（大目录 / 无意义目录）。
    static let ignoredDirectoryNames: Set<String> = [
        "node_modules", ".git", "Pods", "DerivedData", "Library", ".build", ".svn", ".hg",
    ]

    static let markdownUTType: UTType = UTType("net.daringfireball.markdown") ?? .plainText

    static func isMarkdown(_ url: URL) -> Bool {
        isMarkdownExtension(url.pathExtension)
    }

    static func isMarkdownExtension(_ ext: String) -> Bool {
        !ext.isEmpty && extensions.contains(ext.lowercased())
    }
}
