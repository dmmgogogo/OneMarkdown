import XCTest
@testable import OneMarkdown

final class FileTreeBuilderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("omd-tree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func touch(_ rel: String) throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    private func names(_ node: FileNode) -> [String] {
        (node.children ?? []).map(\.name)
    }

    func testFiltersAndPrunes() throws {
        try touch("b.md")
        try touch("a.markdown")
        try touch("notes.txt")
        try touch("docs/inner.md")
        try touch("empty/only.txt")
        try touch("node_modules/pkg/readme.md")
        try touch(".hidden/secret.md")
        let result = FileTreeBuilder.build(root: root)
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(names(result.root), ["docs", "a.markdown", "b.md"])
        let docs = try XCTUnwrap(result.root.children?.first)
        XCTAssertEqual(names(docs), ["inner.md"])
    }

    func testFinderStyleSorting() throws {
        try touch("file10.md")
        try touch("file2.md")
        try touch("File1.md")
        let result = FileTreeBuilder.build(root: root)
        XCTAssertEqual(names(result.root), ["File1.md", "file2.md", "file10.md"])
    }

    func testDepthLimitPrunesSilently() throws {
        try touch("1/2/3/deep.md")
        try touch("top.md")
        let result = FileTreeBuilder.build(root: root, limits: .init(maxDepth: 2, maxNodes: 5000))
        // 层级过深只静默剪掉，不算“截断”，否则 Downloads 这类目录每次刷新都会弹警告
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(names(result.root), ["top.md"])
    }

    func testNodeLimit() throws {
        for i in 0..<20 { try touch("f\(i).md") }
        let result = FileTreeBuilder.build(root: root, limits: .init(maxDepth: 8, maxNodes: 5))
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.root.children?.count, 5)
    }

    func testSymlinkLoopDoesNotRecurse() throws {
        try touch("a/one.md")
        let link = root.appendingPathComponent("a/loop")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        let result = FileTreeBuilder.build(root: root)
        XCTAssertFalse(result.truncated)
        let a = try XCTUnwrap(result.root.children?.first { $0.name == "a" })
        // loop 指向根（已访问），应被跳过；one.md 保留
        XCTAssertEqual(names(a), ["one.md"])
    }

    func testSymlinkedDirectoryIsFollowedOnce() throws {
        // 指向树外目录的符号链接：应当作目录展示并递归一层
        let external = FileManager.default.temporaryDirectory.appendingPathComponent("omd-ext-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: external) }
        try Data("x".utf8).write(to: external.appendingPathComponent("ext.md"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linkdir"), withDestinationURL: external)
        try touch("local.md")
        let result = FileTreeBuilder.build(root: root)
        XCTAssertEqual(names(result.root), ["linkdir", "local.md"])
        let linkdir = try XCTUnwrap(result.root.children?.first)
        XCTAssertTrue(linkdir.isDirectory)
        XCTAssertEqual(names(linkdir), ["ext.md"])
    }

    func testDanglingSymlinkSkipped() throws {
        try touch("ok.md")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("dangling.md"), withDestinationURL: root.appendingPathComponent("nope.md"))
        let result = FileTreeBuilder.build(root: root)
        XCTAssertEqual(names(result.root), ["ok.md"])
    }

    func testUnreadableRootReportsError() throws {
        let missing = root.appendingPathComponent("does-not-exist")
        let result = FileTreeBuilder.build(root: missing)
        XCTAssertNotNil(result.rootError)
        XCTAssertEqual(result.root.children?.count, 0)
    }

    func testEmptyRootKept() {
        let result = FileTreeBuilder.build(root: root)
        XCTAssertEqual(result.root.url, root)
        XCTAssertEqual(result.root.children?.count, 0)
    }

    func testFilter() throws {
        try touch("readme.md")
        try touch("docs/guide-Install.md")
        try touch("docs/other.md")
        let tree = FileTreeBuilder.build(root: root).root
        XCTAssertEqual(FileTreeBuilder.filter(tree, query: "install").map(\.name), ["guide-Install.md"])
        XCTAssertEqual(FileTreeBuilder.filter(tree, query: "  ").count, 0)
        XCTAssertEqual(FileTreeBuilder.filter(tree, query: "md").count, 3)
    }
}
