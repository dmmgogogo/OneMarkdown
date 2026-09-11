import Foundation

/// 大纲条目，由渲染层从 DOM 中的 h1–h6 提取后回传。
nonisolated struct OutlineItem: Identifiable, Hashable, Codable, Sendable {
    let level: Int
    let text: String
    let id: String
}
