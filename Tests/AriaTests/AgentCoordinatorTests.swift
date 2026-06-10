import XCTest
@testable import Aria

@MainActor
final class AgentCoordinatorTests: XCTestCase {

    private func store() -> AgentStore {
        AgentStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("coord-\(UUID().uuidString).json"))
    }

    private func dueAgent() -> BackgroundAgent {
        BackgroundAgent(name: "hourly check", goal: "do the thing", trigger: .interval(seconds: 60))
    }

    func testSweepRunsDueAgentAndRecordsRun() async {
        let s = store()
        await s.upsert(dueAgent())
        var ranGoals: [String] = []
        let coordinator = AgentCoordinator(
            store: s,
            isBusy: { false },
            runner: { goal in ranGoals.append(goal); return (true, "done: \(goal)") },
            notify: { _, _ in })
        await coordinator.sweep(now: Date())
        XCTAssertEqual(ranGoals, ["do the thing"])
        let runs = await s.recentRuns(5)
        XCTAssertEqual(runs.count, 1)
        XCTAssertTrue(runs[0].ok)
        // Agent stamped → immediately re-sweeping must NOT run it again.
        await coordinator.sweep(now: Date())
        XCTAssertEqual(ranGoals.count, 1)
    }

    func testBusyGateDefersRun() async {
        let s = store()
        await s.upsert(dueAgent())
        var ran = 0
        let coordinator = AgentCoordinator(
            store: s,
            isBusy: { true },
            runner: { _ in ran += 1; return (true, "x") },
            notify: { _, _ in })
        await coordinator.sweep(now: Date())
        XCTAssertEqual(ran, 0, "must not run while Aria is busy")
    }

    func testFailureRecordedAndNotified() async {
        let s = store()
        await s.upsert(dueAgent())
        var notes: [String] = []
        let coordinator = AgentCoordinator(
            store: s,
            isBusy: { false },
            runner: { _ in (false, "could not reach calendar") },
            notify: { title, _ in notes.append(title) })
        await coordinator.sweep(now: Date())
        let runs = await s.recentRuns(5)
        XCTAssertFalse(runs[0].ok)
        XCTAssertEqual(notes.count, 1, "completion (even failed) must notify — never silent")
    }
}
