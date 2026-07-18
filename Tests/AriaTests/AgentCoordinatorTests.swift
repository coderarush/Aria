import XCTest
@testable import Aria

private actor CoordinatorSuspensionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var suspended = false

    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            suspended = true
        }
    }

    func waitUntilSuspended() async {
        while !suspended { await Task.yield() }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

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

    func testGlobalPauseLeavesRunnerAndHistoryUntouched() async {
        let s = store()
        await s.upsert(dueAgent())
        var ran = 0
        let coordinator = AgentCoordinator(
            store: s,
            isEnabled: { false },
            isBusy: { false },
            runner: { _ in ran += 1; return (true, "x") },
            notify: { _, _ in })

        await coordinator.sweep(now: Date())

        XCTAssertEqual(ran, 0)
        let runs = await s.recentRuns(5)
        XCTAssertTrue(runs.isEmpty)
    }

    func testPauseDuringPrecheckPreventsRunnerFromStarting() async {
        let s = store()
        let agent = BackgroundAgent(
            name: "mail check",
            goal: "summarize new mail",
            trigger: .mailMatched(query: "standup"),
            watermark: WatcherCheck.hash("old snapshot"))
        await s.upsert(agent)
        let gate = CoordinatorSuspensionGate()
        var enabled = true
        var ran = 0
        let coordinator = AgentCoordinator(
            store: s,
            isEnabled: { enabled },
            isBusy: { false },
            runner: { _ in ran += 1; return (true, "x") },
            notify: { _, _ in },
            mailSnapshot: { _ in
                await gate.suspend()
                return "new snapshot"
            })

        let sweep = Task { await coordinator.sweep(now: Date()) }
        await gate.waitUntilSuspended()
        enabled = false
        await gate.release()
        await sweep.value

        XCTAssertEqual(ran, 0)
        let runs = await s.recentRuns(5)
        XCTAssertTrue(runs.isEmpty)
    }

    func testDisabledRefreshInvalidatesSuspendedWatcherRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let agent = BackgroundAgent(
            name: "folder check",
            goal: "organize files",
            trigger: .folderChanged(path: directory.path))
        let gate = CoordinatorSuspensionGate()
        var enabled = true
        let coordinator = AgentCoordinator(
            store: store(),
            isEnabled: { enabled },
            isBusy: { false },
            runner: { _ in (true, "x") },
            notify: { _, _ in },
            loadAgents: {
                await gate.suspend()
                return [agent]
            })

        let olderRefresh = Task { await coordinator.refreshWatchers() }
        await gate.waitUntilSuspended()
        enabled = false
        await coordinator.refreshWatchers()
        await gate.release()
        await olderRefresh.value

        XCTAssertEqual(coordinator.activeWatcherCount, 0)
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
