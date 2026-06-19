import XCTest
@testable import Aria

final class Part2AttentionLearningTests: XCTestCase {

    // MARK: - Attention (§40)

    func testIdleContextIsInterruptible() {
        let assessor = AttentionAssessor()
        let state = assessor.assess(PresenceContext(idleSeconds: 300))
        XCTAssertEqual(state.mode, .idle)
        XCTAssertGreaterThanOrEqual(state.interruptibility, 0.5)

        let lowUrgency = Opportunity(title: "x", reason: "", urgency: 0.2,
                                     confidence: 0.5, value: 0.5, interruptCost: 0.2)
        XCTAssertTrue(assessor.allowsInterruption(state, opportunity: lowUrgency))
    }

    func testDeepFocusBlocksLowUrgencyButAllowsHigh() {
        let assessor = AttentionAssessor()
        let state = assessor.assess(PresenceContext(idleSeconds: 0, unfinishedDraft: true))
        XCTAssertEqual(state.mode, .deepFocus)
        XCTAssertLessThan(state.interruptibility, 0.5)

        let low = Opportunity(title: "x", reason: "", urgency: 0.2, confidence: 0.5, value: 0.5, interruptCost: 0.2)
        let high = Opportunity(title: "y", reason: "", urgency: 0.95, confidence: 0.9, value: 0.9, interruptCost: 0.2)
        XCTAssertFalse(assessor.allowsInterruption(state, opportunity: low))
        XCTAssertTrue(assessor.allowsInterruption(state, opportunity: high))
    }

    // MARK: - Learning (§43)

    func testAcceptanceRate() async {
        let engine = LearningEngine()
        await engine.recordSuggestion(accepted: true)
        await engine.recordSuggestion(accepted: true)
        await engine.recordSuggestion(accepted: true)
        await engine.recordSuggestion(accepted: false)
        let rate = await engine.acceptanceRate()
        XCTAssertEqual(rate, 0.75, accuracy: 1e-9)
    }

    func testToolSuccessRate() async {
        let engine = LearningEngine()
        await engine.recordToolResult(tool: "gmail", success: true)
        await engine.recordToolResult(tool: "gmail", success: false)
        let rate = await engine.toolSuccessRate("gmail")
        XCTAssertEqual(rate, 0.5, accuracy: 1e-9)
    }

    func testImprovementsFlagLowAcceptanceAndBadTool() async {
        let engine = LearningEngine()
        for _ in 0..<8 { await engine.recordSuggestion(accepted: false) }
        await engine.recordSuggestion(accepted: true)
        for _ in 0..<4 { await engine.recordToolResult(tool: "flaky", success: false) }
        await engine.recordToolResult(tool: "flaky", success: true)

        let improvements = await engine.improvements()
        XCTAssertTrue(improvements.contains { $0.contains("suggestion") })
        XCTAssertTrue(improvements.contains { $0.contains("flaky") })
    }

    // MARK: - Autonomy levels (§44)

    func testDefaultAutonomyIsSuggest() {
        XCTAssertEqual(AutonomyLevel.default, .suggest)
    }

    func testExecutionGate() {
        XCTAssertFalse(AutonomyLevel.suggest.allowsExecution)
        XCTAssertFalse(AutonomyLevel.prepare.allowsExecution)
        XCTAssertTrue(AutonomyLevel.execute.allowsExecution)
        XCTAssertTrue(AutonomyLevel.autonomous.allowsExecution)
    }
}
