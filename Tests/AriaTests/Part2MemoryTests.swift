import XCTest
@testable import Aria

final class Part2MemoryTests: XCTestCase {

    private func record(importance: Double = 0.5,
                        type: MemoryRecord.MemoryType = .episodic,
                        objectiveID: UUID? = nil,
                        summary: String = "",
                        timestamp: Date = Date(timeIntervalSince1970: 1_000),
                        expiration: Date? = nil) -> MemoryRecord {
        MemoryRecord(type: type, importance: importance, objectiveID: objectiveID,
                     summary: summary, timestamp: timestamp, expiration: expiration)
    }

    // MARK: - ImportanceScorer (§30)

    func testScoreIsProductOfSignals() {
        let scorer = ImportanceScorer(threshold: 0.2)
        let score = scorer.score(.init(novelty: 0.5, utility: 0.5, objectiveRelevance: 0.5))
        XCTAssertEqual(score, 0.125, accuracy: 1e-9)
    }

    func testShouldStoreRespectsThreshold() {
        let scorer = ImportanceScorer(threshold: 0.2)
        XCTAssertFalse(scorer.shouldStore(.init(novelty: 0.5, utility: 0.5, objectiveRelevance: 0.5)))
        XCTAssertTrue(scorer.shouldStore(.init(novelty: 0.8, utility: 0.8, objectiveRelevance: 0.8)))
    }

    // MARK: - MemoryEngine (§27)

    func testStoreAcceptsImportantRecordAndEmits() async {
        let bus = EventBus()
        let engine = MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0.1))
        let stored = await engine.store(record(importance: 0.9))
        XCTAssertTrue(stored)
        let kinds = await bus.replay().map(\.kind)
        XCTAssertTrue(kinds.contains(.memoryStored))
    }

    func testStoreRejectsBelowThreshold() async {
        let engine = MemoryEngine(eventBus: EventBus(), scorer: ImportanceScorer(threshold: 0.5))
        let rec = record(importance: 0.05)
        let stored = await engine.store(rec)
        XCTAssertFalse(stored)
        let got = await engine.get(rec.id)
        XCTAssertNil(got)
    }

    func testAllFiltersByType() async {
        let engine = MemoryEngine(eventBus: EventBus(), scorer: ImportanceScorer(threshold: 0))
        await engine.store(record(importance: 0.9, type: .project, summary: "p"))
        await engine.store(record(importance: 0.9, type: .episodic, summary: "e"))
        let projects = await engine.all(type: .project)
        XCTAssertEqual(projects.map(\.summary), ["p"])
    }

    func testExpireRemovesExpired() async {
        let engine = MemoryEngine(eventBus: EventBus(), scorer: ImportanceScorer(threshold: 0))
        await engine.store(record(importance: 0.9, summary: "live"))
        await engine.store(record(importance: 0.9, summary: "dead",
                                  expiration: Date(timeIntervalSince1970: 100)))
        let removed = await engine.expire(asOf: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(removed, 1)
    }

    // MARK: - ContextualRetrieval (§31)

    func testRetrievePrioritizesObjectiveMatch() {
        let objective = UUID()
        let matching = record(importance: 0.4, objectiveID: objective, summary: "match")
        let other = record(importance: 0.4, summary: "other")
        let result = ContextualRetrieval().retrieve(
            from: [other, matching],
            query: .init(objectiveID: objective, keywords: [], now: Date(timeIntervalSince1970: 2_000), limit: 5))
        XCTAssertEqual(result.first?.id, matching.id)
    }

    func testRetrieveExcludesExpired() {
        let live = record(importance: 0.9, summary: "live")
        let dead = record(importance: 0.9, summary: "dead", expiration: Date(timeIntervalSince1970: 100))
        let result = ContextualRetrieval().retrieve(
            from: [live, dead],
            query: .init(objectiveID: nil, keywords: [], now: Date(timeIntervalSince1970: 200), limit: 5))
        XCTAssertEqual(result.map(\.summary), ["live"])
    }

    func testRetrieveRespectsLimit() {
        let records = (0..<3).map { record(importance: 0.5, summary: "\($0)") }
        let result = ContextualRetrieval().retrieve(
            from: records,
            query: .init(objectiveID: nil, keywords: [], now: Date(timeIntervalSince1970: 2_000), limit: 2))
        XCTAssertEqual(result.count, 2)
    }
}
