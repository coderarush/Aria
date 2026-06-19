import XCTest
@testable import Aria

final class AriaRuntimeTests: XCTestCase {

    func testRuntimeBootsInBootingState() async {
        let runtime = AriaRuntime(eventBus: EventBus())
        let state = await runtime.state
        XCTAssertEqual(state, .booting)
    }

    func testStartTransitionsToIdle() async {
        let runtime = AriaRuntime(eventBus: EventBus())
        await runtime.start()
        let state = await runtime.state
        XCTAssertEqual(state, .idle)
    }

    func testStateTransitionEmitsRuntimeEvent() async {
        let bus = EventBus()
        let runtime = AriaRuntime(eventBus: bus)
        await runtime.start()
        let replay = await bus.replay()
        let stateChanges = replay.filter { $0.kind == .runtimeStateChanged }
        XCTAssertFalse(stateChanges.isEmpty)
        XCTAssertEqual(stateChanges.last?.payload["to"], "idle")
    }

    func testSuspendThenResume() async {
        let runtime = AriaRuntime(eventBus: EventBus())
        await runtime.start()
        await runtime.suspend()
        let paused = await runtime.state
        await runtime.resume()
        let resumed = await runtime.state
        XCTAssertEqual(paused, .paused)
        XCTAssertEqual(resumed, .idle)
    }

    func testRecoverReturnsToIdle() async {
        let runtime = AriaRuntime(eventBus: EventBus())
        await runtime.start()
        await runtime.recover()
        let state = await runtime.state
        XCTAssertEqual(state, .idle)
    }

    func testStopReturnsToBooting() async {
        let runtime = AriaRuntime(eventBus: EventBus())
        await runtime.start()
        await runtime.stop()
        let state = await runtime.state
        XCTAssertEqual(state, .booting)
    }

    func testEmitForwardsToEventBus() async {
        let bus = EventBus()
        let runtime = AriaRuntime(eventBus: bus)
        await runtime.emit(AriaEvent(kind: .taskCompleted, source: "test"))
        let replay = await bus.replay()
        XCTAssertTrue(replay.contains { $0.kind == .taskCompleted })
    }

    func testEnterDrivesArbitraryState() async {
        let runtime = AriaRuntime(eventBus: EventBus())
        await runtime.start()
        await runtime.enter(.executing)
        let state = await runtime.state
        XCTAssertEqual(state, .executing)
    }
}
