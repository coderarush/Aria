import XCTest
@testable import Aria

final class ResearchEngineTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-research-\(UUID().uuidString)", isDirectory: true)
    }

    private static let reportJSON = """
    {"sections":[{"heading":"Notes","content":"Content."}],"keyFindings":["Finding 1"]}
    """

    // MARK: - research()

    func testResearchCallsSearchAndFetch() async {
        var engine = ResearchEngine()
        engine.search = { _ in
            [
                SearchResult(title: "Result 1", url: "https://example.com/1", snippet: "Snippet 1"),
                SearchResult(title: "Result 2", url: "https://example.com/2", snippet: "Snippet 2")
            ]
        }
        engine.fetchPage = { _ in "Fetched page content about the topic." }

        let outcome = await engine.research(topic: "Swift concurrency") { _ in
            """
            {"sections":[{"heading":"Overview","content":"Swift concurrency overview."}],"keyFindings":["Actors prevent data races"]}
            """
        }

        XCTAssertFalse(outcome.report.sections.isEmpty)
        XCTAssertEqual(outcome.report.topic, "Swift concurrency")
    }

    func testResearchDeduplicatesURLs() async {
        var engine = ResearchEngine()
        engine.search = { _ in
            [
                SearchResult(title: "Result A", url: "https://same.com", snippet: ""),
                SearchResult(title: "Result B", url: "https://same.com", snippet: ""),
                SearchResult(title: "Result C", url: "https://other.com", snippet: "")
            ]
        }
        engine.fetchPage = { _ in "Content." }

        let outcome = await engine.research(topic: "dedup test", maxSources: 5) { _ in
            """
            {"sections":[{"heading":"Summary","content":"Deduplication works."}],"keyFindings":[]}
            """
        }

        // Sources should have unique URLs
        let uniqueSources = Set(outcome.report.sources)
        XCTAssertEqual(outcome.report.sources.count, uniqueSources.count)
        XCTAssertFalse(outcome.report.sources.isEmpty)
    }

    func testResearchFallbackOnSynthesisError() async {
        var engine = ResearchEngine()
        engine.search = { _ in
            [SearchResult(title: "T", url: "https://example.com", snippet: "s")]
        }
        engine.fetchPage = { _ in "some content" }

        let outcome = await engine.research(topic: "error test") { _ in
            throw NSError(domain: "test", code: 1, userInfo: nil)
        }

        // Should still return a report (fallback)
        XCTAssertFalse(outcome.report.sections.isEmpty)
        XCTAssertEqual(outcome.report.topic, "error test")
    }

    func testResearchSavesFile() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var engine = ResearchEngine(reportsDirectory: directory)
        engine.search = { _ in
            [SearchResult(title: "T", url: "https://example.com", snippet: "s")]
        }
        engine.fetchPage = { _ in "page content" }

        let topic = "save-test-\(UUID().uuidString)"
        let outcome = await engine.research(topic: topic) { _ in Self.reportJSON }

        XCTAssertNotNil(outcome.savedURL, "Research report should expose its saved file.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.savedURL?.path ?? ""))
    }

    func testResearchReturnsReportWhenSaveFails() async throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let blockedDirectory = parent.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blockedDirectory)

        var engine = ResearchEngine(reportsDirectory: blockedDirectory)
        engine.search = { _ in
            [SearchResult(title: "T", url: "https://example.com", snippet: "s")]
        }
        engine.fetchPage = { _ in "page content" }

        let outcome = await engine.research(topic: "save failure") { _ in Self.reportJSON }

        XCTAssertNil(outcome.savedURL)
        XCTAssertEqual(outcome.report.topic, "save failure")
    }

    func testSearchResultsEmpty() async {
        var engine = ResearchEngine()
        engine.search = { _ in [] }
        engine.fetchPage = { _ in "" }

        let outcome = await engine.research(topic: "empty sources test") { _ in
            """
            {"sections":[{"heading":"No Sources","content":"Nothing found."}],"keyFindings":[]}
            """
        }

        // Should not crash; report returned
        XCTAssertEqual(outcome.report.topic, "empty sources test")
        XCTAssertTrue(outcome.report.sources.isEmpty)
    }
}
