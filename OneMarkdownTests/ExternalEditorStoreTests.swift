import XCTest
@testable import OneMarkdown

@MainActor
final class ExternalEditorStoreTests: XCTestCase {
    /// 系统自带，测试机上一定存在
    private let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    private let textEditBundleID = "com.apple.TextEdit"

    private func makeDefaults() -> UserDefaults {
        let suite = "omd-editor-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeStore(_ defaults: UserDefaults, selfBundleID: String = "com.iamxmm.onemarkdown") -> ExternalEditorStore {
        ExternalEditorStore(defaults: defaults, selfBundleID: selfBundleID)
    }

    /// 造一个 LaunchServices 没收录过的 .app，用来验证路径回退
    private func makeUnregisteredApp(bundleID: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("FakeEditor.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": "FakeEditor",
            "CFBundlePackageType": "APPL",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    func testRememberStoresBundleIDAndResolvesBack() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: textEdit.path), "本机没有 TextEdit")
        let store = makeStore(makeDefaults())
        XCTAssertNil(store.editorURL)
        XCTAssertNil(store.editorName)

        XCTAssertTrue(store.remember(textEdit))
        XCTAssertEqual(store.bundleID, textEditBundleID)
        XCTAssertEqual(store.editorURL?.lastPathComponent, "TextEdit.app")
        // 菜单里不该出现 .app 后缀（用户开了“显示所有文件扩展名”时 displayName 会带上）
        let name = try XCTUnwrap(store.editorName)
        XCTAssertFalse(name.hasSuffix(".app"), "编辑器名不应带扩展名：\(name)")
    }

    func testPersistsAcrossInstances() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: textEdit.path), "本机没有 TextEdit")
        let defaults = makeDefaults()
        XCTAssertTrue(makeStore(defaults).remember(textEdit))
        let reloaded = makeStore(defaults)
        XCTAssertEqual(reloaded.bundleID, textEditBundleID)
        XCTAssertNotNil(reloaded.editorName)
    }

    /// 把自己设为编辑器会变成自己打开自己，必须拒绝且不写入
    func testRejectsItself() {
        let defaults = makeDefaults()
        let store = makeStore(defaults, selfBundleID: textEditBundleID)
        XCTAssertFalse(store.remember(textEdit))
        XCTAssertNil(store.bundleID)
        XCTAssertNil(defaults.string(forKey: ExternalEditorStore.key))
    }

    func testRejectsNonBundlePath() {
        let store = makeStore(makeDefaults())
        XCTAssertFalse(store.remember(URL(fileURLWithPath: "/tmp/not-an-app-\(UUID().uuidString).app")))
        XCTAssertNil(store.bundleID)
    }

    /// 刚解压、装在外置盘的编辑器 LaunchServices 查不到，必须按记下的路径兜底
    func testFallsBackToStoredPathWhenNotRegistered() throws {
        let id = "com.example.omd-fake-editor-\(UUID().uuidString)"
        let app = try makeUnregisteredApp(bundleID: id)
        XCTAssertNil(NSWorkspace.shared.urlForApplication(withBundleIdentifier: id), "这个 App 不该被 LaunchServices 收录")

        let defaults = makeDefaults()
        XCTAssertTrue(makeStore(defaults).remember(app))
        // 重开一次，确认回退路径是从 UserDefaults 读回来的
        let reloaded = makeStore(defaults)
        XCTAssertEqual(reloaded.editorURL?.path, app.path)
        XCTAssertEqual(reloaded.editorName, "FakeEditor")
    }

    /// 编辑器被删掉后不能再返回一个已经不存在的路径
    func testIgnoresStoredPathWhenAppGone() throws {
        let app = try makeUnregisteredApp(bundleID: "com.example.omd-fake-editor-\(UUID().uuidString)")
        let defaults = makeDefaults()
        XCTAssertTrue(makeStore(defaults).remember(app))

        try FileManager.default.removeItem(at: app)
        let reloaded = makeStore(defaults)
        XCTAssertNil(reloaded.editorURL)
        XCTAssertNil(reloaded.editorName)
    }
}
