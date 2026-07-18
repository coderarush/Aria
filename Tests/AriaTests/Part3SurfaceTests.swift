import XCTest
@testable import Aria

private final class FakeSurface: SurfaceProtocol, @unchecked Sendable {
    let kind: SurfaceKind
    private let lock = NSLock()
    private(set) var rendered: [StreamState] = []
    private(set) var handedOffTo: SurfaceKind?
    init(kind: SurfaceKind) { self.kind = kind }
    func render(_ state: StreamState) async { lock.lock(); rendered.append(state); lock.unlock() }
    func update(_ state: StreamState) async { lock.lock(); rendered.append(state); lock.unlock() }
    func dismiss() async {}
    func handoff(to: SurfaceKind) async { lock.lock(); handedOffTo = to; lock.unlock() }
}

final class Part3SurfaceTests: XCTestCase {

    // MARK: - ContextStream (§65)

    func testPublishThenLatest() async {
        let stream = ContextStream()
        await stream.publish(StreamState(objective: "plan week", status: "executing",
                                         attention: "deepFocus", context: "writing", memory: ["m1"]))
        let latest = await stream.latest()
        XCTAssertEqual(latest.objective, "plan week")
        XCTAssertEqual(latest.memory, ["m1"])
    }

    func testSubscribeReceivesPublished() async {
        let stream = ContextStream()
        let subscription = await stream.subscribe()
        await stream.publish(StreamState(objective: "x", status: "idle",
                                         attention: "casual", context: "", memory: []))
        var iterator = subscription.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertEqual(received?.objective, "x")
    }

    // MARK: - ExperienceLayer (§64) — surfaces render, never execute

    func testBroadcastRendersToAllSurfaces() async {
        let layer = ExperienceLayer()
        let desktop = FakeSurface(kind: .desktop)
        let watch = FakeSurface(kind: .watch)
        await layer.register(desktop)
        await layer.register(watch)

        await layer.broadcast(StreamState(objective: "o", status: "idle",
                                          attention: "idle", context: "", memory: []))
        XCTAssertEqual(desktop.rendered.count, 1)
        XCTAssertEqual(watch.rendered.count, 1)
    }

    func testHandoffNotifiesSourceSurface() async {
        let layer = ExperienceLayer()
        let desktop = FakeSurface(kind: .desktop)
        await layer.register(desktop)
        await layer.register(FakeSurface(kind: .phone))
        await layer.handoff(from: .desktop, to: .phone)
        XCTAssertEqual(desktop.handedOffTo, .phone)
    }

    // MARK: - ObjectiveWorkspace (§58)

    func testWorkspaceViewsFilterByStatus() {
        var active = Domain.Objective(title: "active one", intent: "x"); active.start()
        var done = Domain.Objective(title: "done one", intent: "x"); done.complete()
        let workspace = ObjectiveWorkspace(objectives: [active, done])
        XCTAssertEqual(workspace.inView(.active).map(\.id), [active.id])
        XCTAssertEqual(workspace.inView(.completed).map(\.id), [done.id])
    }

    func testWorkspaceSearch() {
        let a = Domain.Objective(title: "write essay", intent: "x")
        let b = Domain.Objective(title: "book flight", intent: "x")
        let workspace = ObjectiveWorkspace(objectives: [a, b])
        XCTAssertEqual(workspace.search("essay").map(\.id), [a.id])
    }

    // MARK: - ExecutionSurfaceState (§57)

    func testExecutionSurfaceFromContract() {
        let contract = ExecutionContract(objectiveID: UUID(), status: .completed,
                                         actions: [UUID(), UUID()],
                                         artifacts: [Domain.Artifact(kind: .file, reference: "/tmp/x")],
                                         verificationPassed: true, duration: 0,
                                         confidence: 1, recoverable: false)
        let state = ExecutionSurfaceState(from: contract, title: "Write report")
        XCTAssertEqual(state.objectiveTitle, "Write report")
        XCTAssertEqual(state.actions.count, 2)
        XCTAssertEqual(state.artifacts, ["/tmp/x"])
        XCTAssertFalse(state.canContinue)   // completed, not recoverable
    }
}
