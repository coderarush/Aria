import XCTest
@testable import Aria

private struct GateLegacy: LegacyExecutor {
    func execute(_ request: BridgeRequest) async -> BridgeResult { BridgeResult(output: "legacy") }
}
private struct GateRuntime: RuntimeExecutor {
    func execute(_ request: BridgeRequest) async -> BridgeResult { BridgeResult(output: "runtime") }
}
private struct GateDraftRule: OpportunityRule {
    func evaluate(_ ctx: PresenceContext) -> Opportunity? {
        guard ctx.unfinishedDraft else { return nil }
        return Opportunity(title: "Finish your draft", reason: "open draft",
                           urgency: 0.6, confidence: 0.8, value: 0.7, interruptCost: 0.2)
    }
}

/// Spec §66 release gate: runtime is the real path (behind a flag), the old
/// path stays available, migration is reversible, execution is observable,
/// trust is measurable, and presence is intact.
final class Part3ReleaseGateTests: XCTestCase {

    func testRuntimeIsRealPathAndReversible() async {
        let bus = EventBus()
        let bridge = RuntimeBridge(stage: .preferred, legacy: GateLegacy(),
                                   runtime: GateRuntime(), eventBus: bus)

        // Runtime is the real path...
        var outcome = await bridge.execute(BridgeRequest(objective: "x"))
        XCTAssertEqual(outcome.served, .runtime)

        // ...and migration is reversible — flip back to legacy instantly.
        await bridge.setStage(.legacy)
        outcome = await bridge.execute(BridgeRequest(objective: "x"))
        XCTAssertEqual(outcome.served, .legacy)
    }

    func testExecutionObservableTrustMeasurablePresenceIntact() async {
        let bus = EventBus()

        // Observable.
        let inspector = AriaInspector()
        await inspector.ingest([AriaEvent(kind: .toolExecuted, source: "t")])
        let actions = await inspector.events(in: .actions)
        XCTAssertFalse(actions.isEmpty)

        // Trust measurable.
        let trust = TrustEngine()
        await trust.recordVerification(passed: true)
        await trust.recordTool(success: true)
        let confidence = await trust.confidence()
        XCTAssertGreaterThan(confidence, 0.5)

        // Presence intact — notices, never executes.
        let detector = OpportunityDetector()
        await detector.addRule(GateDraftRule())
        let presence = PresenceEngine(eventBus: bus, detector: detector,
                                      ranker: OpportunityRanker(),
                                      suggestions: SuggestionEngine(eventBus: bus))
        let made = await presence.observe(PresenceContext(unfinishedDraft: true))
        XCTAssertEqual(made.count, 1)
    }
}
