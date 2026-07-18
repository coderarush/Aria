import XCTest
@testable import Aria

final class Part5MarketTests: XCTestCase {

    // MARK: - AdaptiveExecution (§91)

    func testProfileAdaptsToSignals() {
        let adaptive = AdaptiveExecution()
        XCTAssertEqual(adaptive.profile(trust: 0.2, attention: .working, recentSuccess: 0.9), .careful)
        XCTAssertEqual(adaptive.profile(trust: 0.7, attention: .flow, recentSuccess: 0.5), .deep)
        XCTAssertEqual(adaptive.profile(trust: 0.9, attention: .working, recentSuccess: 0.9), .fast)
        XCTAssertEqual(adaptive.profile(trust: 0.6, attention: .working, recentSuccess: 0.6), .balanced)
    }

    // MARK: - ObjectiveMarket (§92)

    func testQueueOrdersByImportanceAndExcludesDeferredRetired() async {
        let market = ObjectiveMarket()
        let low = await market.submit(title: "low", importance: 0.2, deadline: nil)
        let high = await market.submit(title: "high", importance: 0.9, deadline: nil)
        let deferred = await market.submit(title: "deferred", importance: 0.95, deadline: nil)
        await market.postpone(deferred.id)

        let queue = await market.queue(now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(queue.map(\.id), [high.id, low.id])
    }

    func testNearDeadlineRaisesPriority() async {
        let market = ObjectiveMarket()
        let now = Date(timeIntervalSince1970: 10_000)
        let noDeadline = await market.submit(title: "later", importance: 0.5, deadline: nil)
        let urgent = await market.submit(title: "urgent", importance: 0.5,
                                         deadline: Date(timeIntervalSince1970: 10_600))
        let queue = await market.queue(now: now)
        XCTAssertEqual(queue.first?.id, urgent.id)
        _ = noDeadline
    }

    func testRetireRemovesFromQueue() async {
        let market = ObjectiveMarket()
        let entry = await market.submit(title: "x", importance: 0.9, deadline: nil)
        await market.retire(entry.id)
        let queue = await market.queue(now: Date())
        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - ExecutionPolicyEngine (§93)

    func testEffectivePolicyFallsBackToGlobal() async {
        let engine = ExecutionPolicyEngine(global: ExecutionPolicySet(interruptibility: 0.5, quality: 0.7,
                                                                      timeBudget: 60, costBudget: 1,
                                                                      verificationDepth: 1, failureTolerance: 0.2))
        let effective = await engine.effective(objectiveID: nil, projectID: nil)
        XCTAssertEqual(effective.quality, 0.7, accuracy: 1e-9)
    }

    func testObjectiveOverridesGlobal() async {
        let engine = ExecutionPolicyEngine(global: ExecutionPolicySet(interruptibility: 0.5, quality: 0.7,
                                                                      timeBudget: 60, costBudget: 1,
                                                                      verificationDepth: 1, failureTolerance: 0.2))
        let objective = UUID()
        await engine.setObjective(ExecutionPolicySet(interruptibility: 0.1, quality: 0.99,
                                                     timeBudget: 120, costBudget: 5,
                                                     verificationDepth: 3, failureTolerance: 0.0),
                                  for: objective)
        let effective = await engine.effective(objectiveID: objective, projectID: nil)
        XCTAssertEqual(effective.quality, 0.99, accuracy: 1e-9)
    }
}
