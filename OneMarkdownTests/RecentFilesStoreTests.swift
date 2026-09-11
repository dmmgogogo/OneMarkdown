import XCTest
@testable import OneMarkdown

@MainActor
final class RecentFilesStoreTests: XCTestCase {
    /// 每个用例用独立的 UserDefaults suite，结束时清掉
    private func makeDefaults() -> UserDefaults {
        let suite = "omd-recent-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testAddDedupAndLimit() {
        let store = RecentFilesStore(defaults: makeDefaults(), limit: 3, syncsWithSystem: false)
        store.add(URL(fileURLWithPath: "/tmp/a.md"))
        store.add(URL(fileURLWithPath: "/tmp/b.md"))
        store.add(URL(fileURLWithPath: "/tmp/a.md"))
        XCTAssertEqual(store.urls.map(\.lastPathComponent), ["a.md", "b.md"])
        store.add(URL(fileURLWithPath: "/tmp/c.md"))
        store.add(URL(fileURLWithPath: "/tmp/d.md"))
        XCTAssertEqual(store.urls.map(\.lastPathComponent), ["d.md", "c.md", "a.md"])
    }

    func testPersists() {
        let defaults = makeDefaults()
        RecentFilesStore(defaults: defaults, syncsWithSystem: false).add(URL(fileURLWithPath: "/tmp/p.md"))
        let reloaded = RecentFilesStore(defaults: defaults, syncsWithSystem: false)
        XCTAssertEqual(reloaded.urls.map(\.path), ["/tmp/p.md"])
    }

    func testClear() {
        let defaults = makeDefaults()
        let store = RecentFilesStore(defaults: defaults, syncsWithSystem: false)
        store.add(URL(fileURLWithPath: "/tmp/z.md"))
        store.clear()
        XCTAssertTrue(store.urls.isEmpty)
        XCTAssertEqual(defaults.stringArray(forKey: RecentFilesStore.key) ?? [], [])
    }
}
