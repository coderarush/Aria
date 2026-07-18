import XCTest
@testable import Aria

final class EventBusTests: XCTestCase {

    // MARK: - Emission & subscription

    func testSubscriberReceivesEmittedEvent() async throws {
        let bus = EventBus()
        let stream = await bus.subscribe()
        await bus.emit(AriaEvent(kind: .taskStarted, source: "test"))

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertEqual(received?.kind, .taskStarted)
        XCTAssertEqual(received?.source, "test")
    }

    func testMultipleSubscribersBothReceiveEvent() async throws {
        let bus = EventBus()
        let a = await bus.subscribe()
        let b = await bus.subscribe()
        await bus.emit(AriaEvent(kind: .toolExecuted, source: "tool"))

        var ai = a.makeAsyncIterator()
        var bi = b.makeAsyncIterator()
        let ra = await ai.next()
        let rb = await bi.next()
        XCTAssertEqual(ra?.kind, .toolExecuted)
        XCTAssertEqual(rb?.kind, .toolExecuted)
    }

    // MARK: - Replay buffer

    func testReplayReturnsEmittedEventsInOrder() async throws {
        let bus = EventBus()
        await bus.emit(AriaEvent(kind: .appOpened, source: "1"))
        await bus.emit(AriaEvent(kind: .windowFocused, source: "2"))
        await bus.emit(AriaEvent(kind: .contextChanged, source: "3"))

        let replayed = await bus.replay()
        XCTAssertEqual(replayed.map(\.source), ["1", "2", "3"])
        XCTAssertEqual(replayed.map(\.kind), [.appOpened, .windowFocused, .contextChanged])
    }

    func testReplayBufferIsBounded() async throws {
        let bus = EventBus(replayBufferSize: 2)
        await bus.emit(AriaEvent(kind: .appOpened, source: "1"))
        await bus.emit(AriaEvent(kind: .appOpened, source: "2"))
        await bus.emit(AriaEvent(kind: .appOpened, source: "3"))

        let replayed = await bus.replay()
        XCTAssertEqual(replayed.map(\.source), ["2", "3"], "oldest event evicted")
    }

    // MARK: - Event value semantics

    func testEventCarriesPayloadAndPriority() {
        let event = AriaEvent(kind: .verificationPassed,
                              source: "verifier",
                              payload: ["objective": "abc"],
                              priority: .high)
        XCTAssertEqual(event.payload["objective"], "abc")
        XCTAssertEqual(event.priority, .high)
    }

    func testPriorityIsComparable() {
        XCTAssertLessThan(AriaEvent.Priority.low, AriaEvent.Priority.critical)
        XCTAssertGreaterThan(AriaEvent.Priority.high, AriaEvent.Priority.normal)
    }
}
