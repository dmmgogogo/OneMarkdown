import XCTest
@testable import OneMarkdown

final class MarkdownFileTypesTests: XCTestCase {
    func testExtensionsCaseInsensitive() {
        XCTAssertTrue(MarkdownFileTypes.isMarkdown(URL(fileURLWithPath: "/a/b.md")))
        XCTAssertTrue(MarkdownFileTypes.isMarkdown(URL(fileURLWithPath: "/a/B.MD")))
        XCTAssertTrue(MarkdownFileTypes.isMarkdown(URL(fileURLWithPath: "/a/readme.markdown")))
        XCTAssertTrue(MarkdownFileTypes.isMarkdown(URL(fileURLWithPath: "/a/x.mdx")))
    }

    func testNonMarkdown() {
        XCTAssertFalse(MarkdownFileTypes.isMarkdown(URL(fileURLWithPath: "/a/b.txt")))
        XCTAssertFalse(MarkdownFileTypes.isMarkdown(URL(fileURLWithPath: "/a/README")))
        XCTAssertFalse(MarkdownFileTypes.isMarkdown(URL(fileURLWithPath: "/a/.md")))
        XCTAssertFalse(MarkdownFileTypes.isMarkdownExtension(""))
    }
}
