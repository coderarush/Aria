import XCTest
@testable import Aria

final class PersonalContextTests: XCTestCase {

    private func card(_ id: String, _ source: ContextSource, _ title: String, _ snippet: String,
                      _ ago: TimeInterval = 0) -> ContextCard {
        ContextCard(id: id, source: source, title: title, snippet: snippet,
                    timestamp: Date().addingTimeInterval(-ago))
    }

    // MARK: relevance scorer

    func testRelevanceRanksMatchingCardAboveNonMatching() {
        let match = card("a", .file, "Q3 budget spreadsheet", "~/Downloads/Q3-budget.xlsx")
        let miss  = card("b", .file, "vacation photo", "~/Desktop/beach.jpg")
        let terms = ContextCard.terms("budget spreadsheet")
        XCTAssertGreaterThan(match.relevance(to: terms), miss.relevance(to: terms))
        XCTAssertGreaterThan(match.relevance(to: terms), 0)
        XCTAssertEqual(miss.relevance(to: terms), 0)
    }

    func testTitleMatchBeatsBodyOnlyMatch() {
        let titleHit = card("a", .calendar, "Investor meeting", "Fri 2pm — sync")
        let bodyHit  = card("b", .file, "notes.txt", "reminder to prep for the investor meeting")
        let terms = ContextCard.terms("investor meeting")
        XCTAssertGreaterThan(titleHit.relevance(to: terms), bodyHit.relevance(to: terms),
                             "title match should outrank a body-only match")
    }

    func testEmptyTermsScoreZero() {
        let c = card("a", .file, "anything", "anything at all")
        XCTAssertEqual(c.relevance(to: []), 0)
    }

    // MARK: search ranking (pure)

    func testSearchOrdersByRelevance() {
        let cards = [
            card("a", .file, "old receipt", "~/Downloads/receipt.pdf"),
            card("b", .calendar, "design review", "Mon — design review of the new orb"),
            card("c", .file, "design-spec.md", "~/Desktop/design-spec.md")
        ]
        let hits = PersonalContextEngine.rank("design spec", in: cards, limit: 8)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.id, "c", "title-matching design-spec card should rank first")
    }

    func testSearchRespectsLimit() {
        let cards = (0..<20).map { i in
            card("c\(i)", .file, "report \(i)", "quarterly report number \(i)")
        }
        let hits = PersonalContextEngine.rank("report quarterly", in: cards, limit: 5)
        XCTAssertEqual(hits.count, 5)
    }

    func testEmptyQueryReturnsNothing() {
        let cards = [card("a", .file, "thing", "a thing here")]
        XCTAssertTrue(PersonalContextEngine.rank("", in: cards, limit: 8).isEmpty)
        XCTAssertTrue(PersonalContextEngine.rank("   ", in: cards, limit: 8).isEmpty)
    }

    func testEmptyCorpusReturnsNothing() {
        XCTAssertTrue(PersonalContextEngine.rank("anything", in: [], limit: 8).isEmpty)
    }

    func testNonMatchingQueryReturnsNothing() {
        let cards = [card("a", .file, "cat pictures", "~/Downloads/cats.zip")]
        XCTAssertTrue(PersonalContextEngine.rank("quarterly tax filing", in: cards, limit: 8).isEmpty)
    }

    // MARK: codable round-trip (persistence shape)

    func testContextCardCodableRoundTrip() throws {
        let original = card("calendar:abc", .calendar, "Standup", "Mon 9am — Standup", 60)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ContextCard.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.source, .calendar)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.snippet, original.snippet)
    }

    // MARK: opt-in gating

    func testDisabledByDefault() async {
        let d = UserDefaults(suiteName: "pc-\(UUID().uuidString)")!
        let engine = PersonalContextEngine(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("pc-\(UUID().uuidString).json"),
            defaults: d)
        let enabled = await engine.isEnabled
        XCTAssertFalse(enabled, "personal context must be opt-in (default off)")
    }

    func testToolReportsOffWhenDisabled() async throws {
        let d = UserDefaults(suiteName: "pc-tool-\(UUID().uuidString)")!
        let engine = PersonalContextEngine(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("pc-tool-\(UUID().uuidString).json"),
            defaults: d)
        let tool = PersonalContextTool(engine: engine)
        let result = try await tool.run(input: ["query": "anything"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("off"), result.output)
    }

    func testToolMissingQueryThrows() async {
        let tool = PersonalContextTool(engine: PersonalContextEngine(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("pc-mq-\(UUID().uuidString).json")))
        do {
            _ = try await tool.run(input: [:])
            XCTFail("expected missingInput")
        } catch {}
    }

    // MARK: v2 sources

    func testNewSourcesRankAlongsideFiles() {
        let cards = [
            card("app:xcode", .app, "Xcode", "Active right now"),
            card("message:0", .message, "Recent message", "lunch at noon with sara"),
            card("file:/x/report.pdf", .file, "report.pdf", "/x/report.pdf"),
        ]
        XCTAssertEqual(PersonalContextEngine.rank("lunch", in: cards, limit: 8).first?.source, .message)
        XCTAssertEqual(PersonalContextEngine.rank("xcode", in: cards, limit: 8).first?.source, .app)
    }

    func testAllSourcesCodableRoundTrip() throws {
        for source in [ContextSource.file, .calendar, .mail, .app, .message] {
            let c = card("id", source, "t", "s")
            let data = try JSONEncoder().encode(c)
            let back = try JSONDecoder().decode(ContextCard.self, from: data)
            XCTAssertEqual(back.source, source)
        }
    }
}
