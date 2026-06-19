import XCTest
@testable import Aria

private struct DraftRule: OpportunityRule {
    func evaluate(_ ctx: PresenceContext) -> Opportunity? {
        guard ctx.unfinishedDraft else { return nil }
        return Opportunity(title: "Finish your draft", reason: "a draft is open",
                           urgency: 0.6, confidence: 0.8, value: 0.7, interruptCost: 0.2)
    }
}

/// Spec §47 release gate: the user can stop, return later, continue naturally,
/// trust suggestions, and recover instantly. One test exercising the Part 2
/// stack together over a shared EventBus.
final class Part2ReleaseGateTests: XCTestCase {

    func testStopReturnContinueTrustRecover() async {
        let bus = EventBus()
        let objective = UUID()

        // STOP — checkpoint the work in progress.
        let continuity = ContinuityEngine(eventBus: bus)
        let checkpoint = await continuity.checkpoint(objectiveID: objective, kind: .milestone,
                                                     tools: ["draft"], state: .executing)

        // RETURN LATER — resume the most recent work.
        let resumed = await continuity.resumeLatest()
        XCTAssertEqual(resumed?.objectiveID, objective)

        // CONTINUE — pick this objective back up specifically.
        let continued = await continuity.resume(objective: objective)
        XCTAssertEqual(continued?.id, checkpoint.id)

        // TRUST SUGGESTIONS — presence offers, user accepts (nothing auto-runs).
        let suggestions = SuggestionEngine(eventBus: bus)
        let detector = OpportunityDetector()
        await detector.addRule(DraftRule())
        let presence = PresenceEngine(eventBus: bus, detector: detector,
                                      ranker: OpportunityRanker(), suggestions: suggestions)
        let made = await presence.observe(PresenceContext(unfinishedDraft: true))
        XCTAssertEqual(made.count, 1)
        await suggestions.accept(made[0].id)
        let stats = await suggestions.stats()
        XCTAssertEqual(stats.accepted, 1)

        // RECOVER — restore the exact checkpoint state.
        let recovered = await continuity.restore(checkpoint.id)
        XCTAssertEqual(recovered?.tools, ["draft"])
        XCTAssertEqual(recovered?.state, RuntimeState.executing.rawValue)

        // MEMORY persists and is retrievable by objective + keyword.
        let memory = MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0))
        let record = MemoryRecord(type: .project, importance: 0.9,
                                  objectiveID: objective, summary: "drafting the essay")
        await memory.store(record)
        let all = await memory.all()
        let hits = ContextualRetrieval().retrieve(
            from: all,
            query: .init(objectiveID: objective, keywords: ["essay"], now: Date(), limit: 5))
        XCTAssertEqual(hits.first?.id, record.id)
    }
}
