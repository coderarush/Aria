import XCTest
@testable import Aria

final class KnowledgeSettingsTests: XCTestCase {

    func testDefaultsToNoFoldersDisabled() {
        let d = UserDefaults(suiteName: "ks-\(UUID().uuidString)")!
        let s = KnowledgeSettings.load(d)
        XCTAssertTrue(s.folders.isEmpty)
        XCTAssertFalse(s.enabled)
    }

    func testRoundTrip() {
        let d = UserDefaults(suiteName: "ks-rt-\(UUID().uuidString)")!
        var s = KnowledgeSettings.load(d)
        s.enabled = true
        s.folders = ["~/Documents/Projects", "~/Notes"]
        s.save(d)
        let r = KnowledgeSettings.load(d)
        XCTAssertTrue(r.enabled)
        XCTAssertEqual(r.folders, ["~/Documents/Projects", "~/Notes"])
    }
}

final class KnowledgeSearchToolTests: XCTestCase {

    func testSearchToolReturnsFormattedHits() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "The quarterly target is 40 waitlist signups.".data(using: .utf8)!
            .write(to: dir.appendingPathComponent("goals.md"))

        let index = KnowledgeIndex(storeURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("ktool-store-\(UUID().uuidString).json"))
        _ = await index.reindex(folders: [dir.path])

        let tool = KnowledgeSearchTool(index: index)
        let result = try await tool.run(input: ["query": "quarterly waitlist target"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("goals"), result.output)
        XCTAssertTrue(result.output.contains("40 waitlist signups"), result.output)
    }

    func testEmptyIndexSaysSoHonestly() async throws {
        let index = KnowledgeIndex(storeURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("ktool-empty-\(UUID().uuidString).json"))
        let tool = KnowledgeSearchTool(index: index)
        let result = try await tool.run(input: ["query": "anything at all"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("nothing"), result.output)
    }

    func testMissingQueryFails() async {
        let tool = KnowledgeSearchTool(index: KnowledgeIndex(storeURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("ktool-mq-\(UUID().uuidString).json")))
        do {
            _ = try await tool.run(input: [:])
            XCTFail("expected missingInput")
        } catch {}
    }
}
