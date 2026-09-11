import Foundation

/// JS → Swift 的消息。载荷由 WKScriptMessage.body（字典）解码。
nonisolated enum BridgeMessage: Sendable {
    case ready
    case outline([OutlineItem])
    case rendered(docId: String, ms: Double)
    case findResult(current: Int, total: Int)
    case error(String)

    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready":
            self = .ready
        case "outline":
            let raw = dict["items"] as? [[String: Any]] ?? []
            let items = raw.compactMap { item -> OutlineItem? in
                guard let level = item["level"] as? Int,
                      let text = item["text"] as? String,
                      let id = item["id"] as? String else { return nil }
                return OutlineItem(level: level, text: text, id: id)
            }
            self = .outline(items)
        case "rendered":
            self = .rendered(docId: dict["docId"] as? String ?? "", ms: dict["ms"] as? Double ?? 0)
        case "findResult":
            self = .findResult(current: dict["current"] as? Int ?? 0, total: dict["total"] as? Int ?? 0)
        case "error":
            self = .error(dict["message"] as? String ?? "未知错误")
        default:
            return nil
        }
    }
}
