import XCTest
@testable import Aria

final class Part5InitiativeReviewTests: XCTestCase {

    // MARK: - InitiativeEngine (§98) — never executes

    func testRaiseCreatesPendingInitiative() async {
        let engine = InitiativeEngine(maxLevel: .recommend)
        _ = await engine.raise(trigger: .deadline, summary: "deadline soon", suggestedLevel: .suggest)
        let pending = await engine.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.level, .suggest)
    }

    func testLevelCappedByPolicyNeverExecutes() async {
        let engine = InitiativeEngine(maxLevel: .suggest)
        let initiative = await engine.raise(trigger: .repetition, summary: "x", suggestedLevel: .recommend)
        // Capped to the policy max; never reaches execution (max is awaitApproval).
        XCTAssertEqual(initiative.level, .suggest)
        XCTAssertLessThanOrEqual(initiative.level, .awaitApproval)
    }

    // MARK: - ReviewEngine (§99)

    func testCloseCompletedObjective() async {
        let bus = EventBus()
        let review = ReviewEngine(memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)))
        let contract = ExecutionContract(objectiveID: UUID(), status: .completed, actions: [UUID()],
                                         artifacts: [], verificationPassed: true, duration: 0,
                                         confidence: 1, recoverable: false)
        let report = await review.close(contract: contract, learned: "worked well")
        XCTAssertTrue(report.completed)
        XCTAssertTrue(report.verified)
        XCTAssertTrue(report.archived)
        XCTAssertFalse(report.delegateFurther)
    }

    func testCloseFailedRecommendsDelegation() async {
        let bus = EventBus()
        let review = ReviewEngine(memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)))
        let contract = ExecutionContract(objectiveID: UUID(), status: .failed, actions: [],
                                         artifacts: [], verificationPassed: false, duration: 0,
                                         confidence: 0, recoverable: true)
        let report = await review.close(contract: contract, learned: "blocked on auth")
        XCTAssertFalse(report.completed)
        XCTAssertTrue(report.delegateFurther)
    }

    // MARK: - HorizonEngine (§100)

    func testPlanRebalanceCompress() async {
        let engine = HorizonEngine()
        await engine.plan("write essay", at: .today)
        await engine.plan("write essay", at: .today)   // duplicate
        await engine.plan("book flight", at: .week)

        await engine.compress(.today)
        let today = await engine.items(at: .today)
        XCTAssertEqual(today, ["write essay"])

        await engine.rebalance(from: .week, to: .today)
        let afterRebalance = await engine.items(at: .today)
        XCTAssertTrue(afterRebalance.contains("book flight"))
    }
}
