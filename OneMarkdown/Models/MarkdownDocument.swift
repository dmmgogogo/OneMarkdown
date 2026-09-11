import Foundation

/// 已载入内存的 Markdown 文档。
nonisolated struct MarkdownDocument: Sendable {
    /// 用户打开时使用的路径（可能是符号链接）。
    let url: URL
    /// 解析符号链接后的真实路径，用于监听与最近列表。
    let resolvedURL: URL
    let text: String
    /// 实际使用的编码名称，非 UTF-8 时用于提示。
    let encodingName: String
    /// 解码时是否发生有损转换。
    let isLossy: Bool
    let byteCount: Int
    let modifiedAt: Date?

    var title: String { url.deletingPathExtension().lastPathComponent }
    var directoryURL: URL { url.deletingLastPathComponent() }
    var isUTF8: Bool { encodingName == "UTF-8" }
}
