import XCTest
@testable import Aria

private struct UnfinishedDraftRule: OpportunityRule {
    func evaluate(_ ctx: PresenceContext) -> Opportunity? {
        guard ctx.unfinishedDraft else { return nil }
        return Opportunity(title: "Finish your draft", reason: "a draft is open",
                           urgency: 0.6, confidence: 0.8, value: 0.7, interruptCost: 0.2)
    }
}

final class Part2PresenceTests: XCTestCase {

    // MARK: - OpportunityRanker (§38)

    func testRankerOrdersByScore() {
        let strong = Opportunity(title: "a", reason: "", urgency: 0.9, confidence: 0.9, value: 0.9, interruptCost: 0.0)
        let weak = Opportunity(title: "b", reason: "", urgency: 0.5, confidence: 0.5, value: 0.5, interruptCost: 0.4)
        let ranked = OpportunityRanker().rank([weak, strong])
        XCTAssertEqual(ranked.map(\.id), [strong.id, weak.id])
    }

    // MARK: - OpportunityDetector (§38)

    func testDetectorFiresMatchingRule() async {
        let detector = OpportunityDetector()
        await detector.addRule(UnfinishedDraftRule())
        let hits = await detector.detect(PresenceContext(unfinishedDraft: true))
        XCTAssertEqual(hits.count, 1)
        let none = await detector.detect(PresenceContext(unfinishedDraft: false))
        XCTAssertTrue(none.isEmpty)
    }

    // MARK: - SuggestionEngine (§39)

    func testSuggestionLifecycleAndStats() async {
        let bus = EventBus()
        let engine = SuggestionEngine(eventBus: bus)
        let suggestion = await engine.suggest(text: "Finish the summary?")
        XCTAssertEqual(suggestion.state, .pending)

        await engine.accept(suggestion.id)
        let stored = await engine.get(suggestion.id)
        XCTAssertEqual(stored?.state, .accepted)

        let stats = await engine.stats()
        XCTAssertEqual(stats.accepted, 1)

        let kinds = await bus.replay().map(\.kind)
        XCTAssertTrue(kinds.contains(.suggestionOffered))
        XCTAssertTrue(kinds.contains(.suggestionResolved))
    }

    // MARK: - PresenceEngine end to end (§37) — notices, never executes

    func testPresenceObserveProducesRankedSuggestion() async {
        let bus = EventBus()
        let detector = OpportunityDetector()
        await detector.addRule(UnfinishedDraftRule())
        let presence = PresenceEngine(eventBus: bus,
                                      detector: detector,
                                      ranker: OpportunityRanker(),
                                      suggestions: SuggestionEngine(eventBus: bus))

        let made = await presence.observe(PresenceContext(unfinishedDraft: true))
        XCTAssertEqual(made.count, 1)
        XCTAssertTrue(made.first?.text.contains("draft") ?? false)
        XCTAssertEqual(made.first?.state, .pending)
    }

    func testPresenceSilentWhenNoOpportunity() async {
        let presence = PresenceEngine(eventBus: EventBus(),
                                      detector: OpportunityDetector(),
                                      ranker: OpportunityRanker(),
                                      suggestions: SuggestionEngine(eventBus: EventBus()))
        let made = await presence.observe(PresenceContext())
        XCTAssertTrue(made.isEmpty)
    }
}
