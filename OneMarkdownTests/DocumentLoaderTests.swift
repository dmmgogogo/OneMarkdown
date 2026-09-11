import XCTest
@testable import OneMarkdown

final class DocumentLoaderTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("omd-loader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func write(_ data: Data, _ name: String) throws -> URL {
        let url = tmp.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testUTF8() throws {
        let url = try write(Data("# 标题\n\n正文".utf8), "a.md")
        let doc = try DocumentLoader.load(url)
        XCTAssertEqual(doc.text, "# 标题\n\n正文")
        XCTAssertEqual(doc.encodingName, "UTF-8")
        XCTAssertFalse(doc.isLossy)
        XCTAssertEqual(doc.title, "a")
    }

    func testUTF8BOMStripped() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("hello".utf8))
        let doc = try DocumentLoader.load(try write(data, "bom.md"))
        XCTAssertEqual(doc.text, "hello")
        XCTAssertEqual(doc.encodingName, "UTF-8")
    }

    func testUTF16WithBOM() throws {
        // Windows 记事本“Unicode”格式：FF FE + UTF-16LE，每个 ASCII 字符都带 0x00，不能被当成二进制
        var data = Data([0xFF, 0xFE])
        data.append(contentsOf: "# 标题\nhi".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        let doc = try DocumentLoader.load(try write(data, "utf16.md"))
        XCTAssertEqual(doc.text, "# 标题\nhi")
        XCTAssertEqual(doc.encodingName, "UTF-16")
    }

    func testGB18030Fallback() throws {
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let data = try XCTUnwrap("# 中文标题\n\n这是一段中文。".data(using: gbk))
        let doc = try DocumentLoader.load(try write(data, "gbk.md"))
        XCTAssertTrue(doc.text.contains("中文标题"), doc.text)
        XCTAssertNotEqual(doc.encodingName, "UTF-8")
    }

    func testCRLFNormalized() throws {
        let doc = try DocumentLoader.load(try write(Data("a\r\nb\rc\n".utf8), "crlf.md"))
        XCTAssertEqual(doc.text, "a\nb\nc\n")
    }

    func testBinaryRejected() throws {
        var data = Data("text".utf8)
        data.append(contentsOf: [0x00, 0x01, 0x02])
        XCTAssertThrowsError(try DocumentLoader.load(try write(data, "bin.md"))) { error in
            XCTAssertEqual(error as? DocumentLoader.LoadError, .binary)
        }
    }

    func testTooLargeRejected() throws {
        let url = tmp.appendingPathComponent("big.md")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(DocumentLoader.maxBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try DocumentLoader.load(url)) { error in
            if case .tooLarge = error as? DocumentLoader.LoadError {} else { XCTFail("expected tooLarge, got \(error)") }
        }
    }

    func testMissingFile() {
        XCTAssertThrowsError(try DocumentLoader.load(tmp.appendingPathComponent("nope.md"))) { error in
            XCTAssertEqual(error as? DocumentLoader.LoadError, .notFound)
        }
    }

    func testSymlinkResolved() throws {
        let real = try write(Data("real".utf8), "real.md")
        let link = tmp.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let doc = try DocumentLoader.load(link)
        XCTAssertEqual(doc.text, "real")
        XCTAssertEqual(doc.url, link)
        XCTAssertEqual(doc.resolvedURL.standardizedFileURL.path, real.resolvingSymlinksInPath().standardizedFileURL.path)
    }
}
