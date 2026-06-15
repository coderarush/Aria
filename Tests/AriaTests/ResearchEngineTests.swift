import XCTest
@testable import Aria

final class ResearchEngineTests: XCTestCase {

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

        let report = await engine.research(topic: "Swift concurrency") { _ in
            """
            {"sections":[{"heading":"Overview","content":"Swift concurrency overview."}],"keyFindings":["Actors prevent data races"]}
            """
        }

        XCTAssertFalse(report.sections.isEmpty)
        XCTAssertEqual(report.topic, "Swift concurrency")
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

        let report = await engine.research(topic: "dedup test", maxSources: 5) { _ in
            """
            {"sections":[{"heading":"Summary","content":"Deduplication works."}],"keyFindings":[]}
            """
        }

        // Sources should have unique URLs
        let uniqueSources = Set(report.sources)
        XCTAssertEqual(report.sources.count, uniqueSources.count)
        XCTAssertFalse(report.sources.isEmpty)
    }

    func testResearchFallbackOnSynthesisError() async {
        var engine = ResearchEngine()
        engine.search = { _ in
            [SearchResult(title: "T", url: "https://example.com", snippet: "s")]
        }
        engine.fetchPage = { _ in "some content" }

        let report = await engine.research(topic: "error test") { _ in
            throw NSError(domain: "test", code: 1, userInfo: nil)
        }

        // Should still return a report (fallback)
        XCTAssertFalse(report.sections.isEmpty)
        XCTAssertEqual(report.topic, "error test")
    }

    func testResearchSavesFile() async {
        var engine = ResearchEngine()
        engine.search = { _ in
            [SearchResult(title: "T", url: "https://example.com", snippet: "s")]
        }
        engine.fetchPage = { _ in "page content" }

        let topic = "save-test-\(UUID().uuidString)"
        _ = await engine.research(topic: topic) { _ in
            """
            {"sections":[{"heading":"Notes","content":"Content."}],"keyFindings":["Finding 1"]}
            """
        }

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Aria Notes/Research")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let safeTopic = topic.replacingOccurrences(of: " ", with: "-")
        let matchingFile = files.first { $0.lastPathComponent.contains(safeTopic) }
        XCTAssertNotNil(matchingFile, "Research report file should be saved.")

        // Cleanup
        if let file = matchingFile { try? FileManager.default.removeItem(at: file) }
    }

    func testSearchResultsEmpty() async {
        var engine = ResearchEngine()
        engine.search = { _ in [] }
        engine.fetchPage = { _ in "" }

        let report = await engine.research(topic: "empty sources test") { _ in
            """
            {"sections":[{"heading":"No Sources","content":"Nothing found."}],"keyFindings":[]}
            """
        }

        // Should not crash; report returned
        XCTAssertEqual(report.topic, "empty sources test")
        XCTAssertTrue(report.sources.isEmpty)
    }
}
