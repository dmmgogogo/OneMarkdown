import Foundation

/// 读取 Markdown 文件：大小上限、二进制探测、BOM 去除、编码回退、换行归一。
nonisolated enum DocumentLoader {
    enum LoadError: LocalizedError, Equatable {
        case notFound
        case notReadable
        case tooLarge(bytes: Int)
        case binary
        case undecodable

        var errorDescription: String? {
            switch self {
            case .notFound: return "文件不存在或已被移动"
            case .notReadable: return "无法读取该文件，请检查“系统设置 › 隐私与安全性 › 文件和文件夹”中的权限"
            case .tooLarge(let bytes):
                return "文件过大（\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))），超过 \(maxBytes / 1_048_576) MB 上限"
            case .binary: return "这不是文本文件"
            case .undecodable: return "无法识别文件编码"
            }
        }
    }

    /// 超过此大小直接拒绝。
    static let maxBytes = 20 * 1_048_576
    /// 超过此大小仍然加载，但提示“渲染可能较慢”。
    static let largeWarningBytes = 5 * 1_048_576

    /// 编码探测顺序（UTF-8 失败后）。
    private static let fallbackEncodings: [String.Encoding] = [
        .utf8,
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))),
        .shiftJIS,
        .japaneseEUC,
        .windowsCP1252,
    ]

    static func load(_ url: URL) throws -> MarkdownDocument {
        let fm = FileManager.default
        let resolved = url.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: resolved.path) else { throw LoadError.notFound }

        let attrs = try? fm.attributesOfItem(atPath: resolved.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        if size > maxBytes { throw LoadError.tooLarge(bytes: size) }

        // 不用 mmap：热重载时文件可能正被编辑器截断，映射页失效会直接 SIGBUS
        let data: Data
        do {
            data = try Data(contentsOf: resolved)
        } catch {
            throw LoadError.notReadable
        }

        if looksBinary(data) { throw LoadError.binary }

        let (text, encodingName, lossy) = try decode(data)
        return MarkdownDocument(
            url: url,
            resolvedURL: resolved,
            text: normalizeLineEndings(text),
            encodingName: encodingName,
            isLossy: lossy,
            byteCount: data.count,
            modifiedAt: attrs?[.modificationDate] as? Date
        )
    }

    /// 前 8 KB 含 NUL 字节视为二进制；UTF-16 文本天然带 NUL，先按 BOM 放行。
    static func looksBinary(_ data: Data) -> Bool {
        if hasUTF16BOM(data) { return false }
        let head = data.prefix(8192)
        return head.contains(0)
    }

    static func hasUTF16BOM(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
    }

    /// 返回 (文本, 编码名, 是否有损)。
    static func decode(_ data: Data) throws -> (String, String, Bool) {
        var body = data
        // UTF-8 BOM
        if body.starts(with: [0xEF, 0xBB, 0xBF]) {
            body = body.dropFirst(3)
            if let s = String(data: body, encoding: .utf8) { return (s, "UTF-8", false) }
        }
        // UTF-16 BOM（String(data:encoding:.utf16) 会自行识别字节序并去掉 BOM）
        if hasUTF16BOM(body) {
            if let s = String(data: body, encoding: .utf16) { return (s, "UTF-16", false) }
            throw LoadError.undecodable
        }
        if let s = String(data: body, encoding: .utf8) { return (s, "UTF-8", false) }

        // 让系统按候选编码探测
        var converted: NSString?
        var usedLossy: ObjCBool = false
        let options: [StringEncodingDetectionOptionsKey: Any] = [
            .suggestedEncodingsKey: fallbackEncodings.map(\.rawValue),
            .allowLossyKey: false,
        ]
        let detected = NSString.stringEncoding(for: body, encodingOptions: options, convertedString: &converted, usedLossyConversion: &usedLossy)
        if detected != 0, let converted {
            return (converted as String, encodingDisplayName(String.Encoding(rawValue: detected)), usedLossy.boolValue)
        }
        // 最后兜底：Latin-1 一定成功但可能乱码
        if let s = String(data: body, encoding: .isoLatin1) { return (s, "ISO-8859-1", true) }
        throw LoadError.undecodable
    }

    static func encodingDisplayName(_ encoding: String.Encoding) -> String {
        let cf = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
        if let name = CFStringConvertEncodingToIANACharSetName(cf) as String? {
            return name.uppercased()
        }
        return encoding.description
    }

    static func normalizeLineEndings(_ text: String) -> String {
        guard text.contains("\r") else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
