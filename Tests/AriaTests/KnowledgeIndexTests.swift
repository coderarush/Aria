import XCTest
@testable import Aria

final class KnowledgeIndexTests: XCTestCase {

    private var dir: URL!
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kidx-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Store lives OUTSIDE the indexed folder (mirrors production: App Support
        // vs user folders) — and the index also guards against indexing itself.
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kidx-store-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func write(_ name: String, _ content: String) {
        try? content.data(using: .utf8)?.write(to: dir.appendingPathComponent(name))
    }

    func testIndexesFolderAndFindsContent() async {
        write("pricing.md", "# Investor call\nThe investor said pricing should be $29 one-time, not subscription.")
        write("recipe.txt", "Pasta: boil water, add salt, cook 9 minutes.")
        let index = KnowledgeIndex(storeURL: storeURL)
        let stats = await index.reindex(folders: [dir.path])
        XCTAssertEqual(stats.indexed, 2)

        let hits = await index.search("what did the investor say about pricing", limit: 3)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits[0].path.hasSuffix("pricing.md"))
        XCTAssertTrue(hits[0].snippet.contains("$29"))
    }

    func testIncrementalSkipsUnchangedFiles() async {
        write("a.md", "alpha content here")
        let index = KnowledgeIndex(storeURL: storeURL)
        _ = await index.reindex(folders: [dir.path])
        let second = await index.reindex(folders: [dir.path])
        XCTAssertEqual(second.indexed, 0, "unchanged files must be skipped")
        XCTAssertEqual(second.skipped, 1)
    }

    func testReindexPicksUpModifiedFiles() async throws {
        write("a.md", "first version about apples")
        let index = KnowledgeIndex(storeURL: storeURL)
        _ = await index.reindex(folders: [dir.path])
        try await Task.sleep(nanoseconds: 1_100_000_000)   // mtime resolution
        write("a.md", "second version about oranges")
        let stats = await index.reindex(folders: [dir.path])
        XCTAssertEqual(stats.indexed, 1)
        let hits = await index.search("oranges", limit: 3)
        XCTAssertEqual(hits.count, 1)
        let stale = await index.search("apples", limit: 3)
        XCTAssertTrue(stale.isEmpty, "old content must be replaced")
    }

    func testRemovedFilesDropOut() async {
        write("gone.md", "ephemeral zanzibar text")
        let index = KnowledgeIndex(storeURL: storeURL)
        _ = await index.reindex(folders: [dir.path])
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("gone.md"))
        _ = await index.reindex(folders: [dir.path])
        let hits = await index.search("zanzibar", limit: 3)
        XCTAssertTrue(hits.isEmpty)
    }

    func testPersistsAcrossInstances() async {
        write("keep.md", "durable xylophone fact")
        let i1 = KnowledgeIndex(storeURL: storeURL)
        _ = await i1.reindex(folders: [dir.path])
        let i2 = KnowledgeIndex(storeURL: storeURL)
        let hits = await i2.search("xylophone", limit: 3)
        XCTAssertEqual(hits.count, 1)
    }

    func testSurvivesCorruptStore() async {
        try? Data("}{garbage".utf8).write(to: storeURL)
        let index = KnowledgeIndex(storeURL: storeURL)
        let hits = await index.search("anything", limit: 3)
        XCTAssertTrue(hits.isEmpty)
    }

    func testSearchRanksTitleMatchesHigher() async {
        write("meeting-notes.md", "general notes about many things and stuff")
        write("other.md", "this file mentions meeting once in passing in body text only here")
        let index = KnowledgeIndex(storeURL: storeURL)
        _ = await index.reindex(folders: [dir.path])
        let hits = await index.search("meeting notes", limit: 2)
        XCTAssertEqual(hits.first?.title, "meeting-notes")
    }
}
