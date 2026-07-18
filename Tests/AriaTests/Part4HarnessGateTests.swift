import XCTest
@testable import Aria

final class Part4HarnessGateTests: XCTestCase {

    private func perceptionEngine() -> PerceptionEngine {
        PerceptionEngine(bus: ObservationBus(), store: PerceptionStore(maxRetained: 100),
                         policy: ObservationPolicy(minConfidence: 0.5, maxRetained: 100))
    }

    // MARK: - PerceptionHarness (§84)

    func testHarnessMeasuresRelevance() async {
        let harness = PerceptionHarness(perception: perceptionEngine(), target: 0.95)
        let scenarios = [
            PerceptionScenario(observation: Observation(source: "screen", confidence: 0.9), expectedRelevant: true),
            PerceptionScenario(observation: Observation(source: "noise", confidence: 0.1), expectedRelevant: false),
        ]
        let report = await harness.evaluate(scenarios)
        XCTAssertEqual(report.relevanceRate, 1.0, accuracy: 1e-9)
        XCTAssertTrue(report.meetsTarget)
    }

    func testHarnessFlagsMisperception() async {
        let harness = PerceptionHarness(perception: perceptionEngine(), target: 0.95)
        // High confidence but expected irrelevant → admitted wrongly.
        let scenarios = [
            PerceptionScenario(observation: Observation(source: "noise", confidence: 0.9), expectedRelevant: false),
        ]
        let report = await harness.evaluate(scenarios)
        XCTAssertEqual(report.relevanceRate, 0.0, accuracy: 1e-9)
        XCTAssertFalse(report.meetsTarget)
    }

    // MARK: - §86 release gate

    func testPart4ReleaseGate() async {
        let bus = EventBus()

        // Understands activity.
        let coding = ScreenUnderstanding(app: "Xcode", intent: "coding", entities: [],
                                         relevance: 0.7, confidence: 0.8)
        XCTAssertEqual(ActivityDetector().detect(screen: coding, audio: nil,
                                                 idleSeconds: 0, focusSeconds: 60), .working)

        // Maintains context (fusion).
        let unified = await FusionEngine().fuse(
            [Observation(source: "screen", confidence: 0.9, payload: ["summary": "coding"],
                         timestamp: Date(timeIntervalSince1970: 1_000))],
            now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(unified.current, "coding")

        // Switches surfaces (mesh handoff).
        let handoff = ContextHandoff()
        await handoff.send(HandoffBundle(objectiveID: nil, memory: ["m"], attention: "working",
                                         status: "executing", artifacts: []), to: .phone)
        let received = await handoff.receive(on: .phone)
        XCTAssertEqual(received?.memory, ["m"])

        // Glass UI works without hardware.
        let glass = GlassRuntime()
        await glass.render(StreamState(objective: "plan", status: "executing",
                                       attention: "working", context: "coding", memory: ["m"]))
        let hud = await glass.hud
        XCTAssertEqual(hud.objective, "plan")

        // Recalls correctly.
        let continuity = ContinuityEngine(eventBus: bus)
        let memory = MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0))
        _ = await continuity.checkpoint(objectiveID: UUID(), tools: ["draft"], state: .executing)
        let bundle = await RecallEngine(continuity: continuity, memory: memory).recall()
        XCTAssertEqual(bundle.recentActions, ["draft"])

        // Does NOT execute — perception/glass expose no execution API (compile-time).
    }
}
