import XCTest
@testable import Aria

final class TaskStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-task-\(UUID().uuidString)/active-task.json")
    }

    private func samplePlan() -> [TaskStep] {
        var s1 = TaskStep(summary: "Research A", executor: .agent("Orion"), input: ["q": "a"])
        s1.status = .done; s1.result = "facts A"
        var s2 = TaskStep(summary: "Save it", executor: .tool("save_note"), input: [:])
        s2.postCondition = .resultContains("saved")
        s2.status = .pending
        return [s1, s2]
    }

    func testSnapshotRoundTripsThroughRestore() {
        let snap = PersistedTask.snapshot(goal: "do x", steps: samplePlan(), lastOutput: "facts A")
        XCTAssertEqual(snap.steps.count, 2)
        XCTAssertEqual(snap.resumeIndex, 1)            // first non-done step
        XCTAssertFalse(snap.isFinished)
        XCTAssertEqual(snap.unfinishedCount, 1)

        let restored = snap.restoredSteps()
        XCTAssertEqual(restored[0].status, .done)
        XCTAssertEqual(restored[0].result, "facts A")
        XCTAssertEqual(restored[0].executor, .agent("Orion"))
        XCTAssertEqual(restored[1].executor, .tool("save_note"))
        XCTAssertEqual(restored[1].status, .pending)
        XCTAssertEqual(restored[1].postCondition, .resultContains("saved"))

        let pairs = snap.completedPairs()
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.output, "facts A")
    }

    func testInterruptedRunStatusBecomesPending() {
        var s = TaskStep(summary: "x", executor: .tool("shell"), input: [:])
        s.status = .running   // app died mid-step
        let snap = PersistedTask.snapshot(goal: "g", steps: [s], lastOutput: "")
        XCTAssertEqual(snap.steps[0].status, "pending")   // resumes, not stuck "running"
        XCTAssertEqual(snap.resumeIndex, 0)
    }

    func testFinishedSnapshotHasNoResume() {
        var s = TaskStep(summary: "x", executor: .tool("notify"), input: [:])
        s.status = .done
        let snap = PersistedTask.snapshot(goal: "g", steps: [s], lastOutput: "out")
        XCTAssertTrue(snap.isFinished)
        XCTAssertEqual(snap.resumeIndex, 1)               // == count, nothing to resume
    }

    func testStoreSaveLoadPendingClear() async {
        let store = TaskStore(url: tempURL())
        let before = await store.pending()
        XCTAssertNil(before)
        let snap = PersistedTask.snapshot(goal: "g", steps: samplePlan(), lastOutput: "facts A")
        await store.save(snap)
        let pend = await store.pending()
        XCTAssertEqual(pend?.goal, "g")                   // unfinished → resumable
        await store.clear()
        let after = await store.pending()
        XCTAssertNil(after)
    }

    func testSaveAndClearPublishTaskStoreChanges() async {
        let store = TaskStore(url: tempURL())
        let saved = expectation(forNotification: .ariaTaskStoreDidChange, object: nil)
        await store.save(PersistedTask.snapshot(goal: "g", steps: samplePlan(), lastOutput: ""))
        await fulfillment(of: [saved], timeout: 1)

        let cleared = expectation(forNotification: .ariaTaskStoreDidChange, object: nil)
        await store.clear()
        await fulfillment(of: [cleared], timeout: 1)
    }

    func testCurrentTaskDistinguishesLiveRunFromRelaunchResume() async {
        let url = tempURL()
        let runningStore = TaskStore(url: url)
        let snap = PersistedTask.snapshot(goal: "prepare briefing", steps: samplePlan(), lastOutput: "facts A")
        await runningStore.save(snap)

        let running = await runningStore.currentTask()
        let relaunchedStore = TaskStore(url: url)
        let resumable = await relaunchedStore.currentTask()

        XCTAssertEqual(running?.state, .running)
        XCTAssertEqual(running?.task.goal, "prepare briefing")
        XCTAssertEqual(resumable?.state, .resumable)
        await runningStore.clear()
    }

    func testResumeIntent() {
        XCTAssertTrue(ResumeIntent.matches("resume"))
        XCTAssertTrue(ResumeIntent.matches("pick up where you left off"))
        XCTAssertTrue(ResumeIntent.matches("finish what you started"))
        XCTAssertFalse(ResumeIntent.matches("what's the weather"))
    }

    func testResumeNotificationDoesNotExposeTaskGoal() {
        let goal = "Send the confidential acquisition draft"
        let body = ResumeNotificationPresentation.body(remainingSteps: 2)

        XCTAssertEqual(
            body,
            "An unfinished task is ready to resume (2 steps left). Open Aria or say “resume” to continue."
        )
        XCTAssertFalse(body.localizedCaseInsensitiveContains(goal))
    }

    func testLegacyPersistedTaskWithoutConditionStillDecodes() throws {
        let legacy = """
        {"goal":"g","steps":[{"summary":"Open Notes","kind":"tool","name":"open_app","input":{"name":"Notes"},"status":"pending","result":""}],"lastOutput":"","updatedAt":0}
        """
        let task = try JSONDecoder().decode(PersistedTask.self, from: Data(legacy.utf8))
        XCTAssertEqual(task.restoredSteps().first?.postCondition, PostCondition.none)
    }
}
