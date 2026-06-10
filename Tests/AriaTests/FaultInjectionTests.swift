import XCTest
@testable import Aria

/// Failure-simulation seed (V9 constitution: "Aria should fail safely. Never fail
/// silently... corrupted responses, invalid input, interrupted workflows").
/// Every persisted store and parser must survive garbage without crashing and
/// come back with a sane default.
final class FaultInjectionTests: XCTestCase {

    private func corruptFile(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fault-\(name)-\(UUID().uuidString).json")
        try? Data("{not json at all]]".utf8).write(to: url)
        return url
    }

    // MARK: Corrupted persisted state → safe defaults, no crash

    func testTaskStoreSurvivesCorruptJournal() async {
        let url = corruptFile("task")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TaskStore(url: url)
        let pending = await store.pending()
        XCTAssertNil(pending, "corrupt journal must read as no pending task")
    }

    func testPatternEngineSurvivesCorruptPatternsFile() async {
        let url = corruptFile("patterns")
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = PatternEngine(fileURL: url)
        let patterns = await engine.allPatterns()
        XCTAssertEqual(patterns, [], "corrupt patterns must load as empty")
    }

    func testProactiveStoreSurvivesCorruptFile() {
        let url = corruptFile("proactive")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProactiveStoreFile.load(from: url)
        XCTAssertFalse(store.isSuppressed(key: "anything", now: Date(timeIntervalSince1970: 0)))
    }

    func testTaskStoreSurvivesTruncatedJournal() async {
        // A crash mid-write leaves a truncated valid-prefix file.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fault-truncated-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try? Data(#"{"goal": "organize fil"#.utf8).write(to: url)
        let store = TaskStore(url: url)
        let pending = await store.pending()
        XCTAssertNil(pending)
    }

    // MARK: Corrupted provider responses → parser yields nothing, no crash

    func testStreamParserSurvivesGarbageChunks() {
        var parser = GeminiStreamParser()
        let garbage = ["data: {broken", "\u{0}\u{1}binary\u{2}", "data: ", "}}}}",
                       "data: {\"candidates\": \"not-an-array\"}"]
        for chunk in garbage {
            _ = parser.consume(chunk)   // must not crash
        }
        XCTAssertTrue(GeminiStreamParser.events(fromJSON: Data("not json".utf8)).isEmpty)
        XCTAssertTrue(GeminiStreamParser.events(fromJSON: Data()).isEmpty)
    }

    // MARK: Invalid user/model input → nil/fail, never crash

    func testInvalidInputsAreRejectedNotFatal() {
        XCTAssertNil(EventDates.parse(nil))
        XCTAssertNil(EventDates.parse(""))
        XCTAssertNil(EventDates.parse("not a date"))
        XCTAssertNil(BrowserTool.normalizedURL(""))
        XCTAssertNil(BrowserTool.normalizedURL("   "))
        XCTAssertNotNil(WebSearchTool.searchURL(query: "weird ☃ query & stuff=true"))
    }

    func testGeminiURLBuilderRejectsNothingButEncodesEverything() throws {
        // Hostile model name / key must produce an encoded URL, never inject paths.
        let url = try XCTUnwrap(GeminiClient.geminiURL(model: "gemini-2.5-flash",
                                                       apiKey: "k&ey=inject?x"))
        XCTAssertTrue(url.absoluteString.contains("key=k%26ey%3Dinject?x")
                      || url.query?.contains("key=k%26ey%3Dinject%3Fx") == true
                      || url.query?.contains("k%26ey") == true,
                      "key must be percent-encoded: \(url.absoluteString)")
    }
}
