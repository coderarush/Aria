import XCTest
@testable import Aria

final class Part3ObservabilityTests: XCTestCase {

    private func sampleEvents() -> [AriaEvent] {
        [
            AriaEvent(kind: .objectiveCreated, source: "obj"),
            AriaEvent(kind: .taskStarted, source: "exec"),
            AriaEvent(kind: .toolExecuted, source: "gmail"),
            AriaEvent(kind: .toolExecuted, source: "slack", payload: ["result": "failed"], priority: .high),
            AriaEvent(kind: .memoryStored, source: "mem"),
            AriaEvent(kind: .presenceOpportunity, source: "presence"),
        ]
    }

    // MARK: - AriaInspector (§56)

    func testCategoryViewsFilter() async {
        let inspector = AriaInspector()
        await inspector.ingest(sampleEvents())

        let objectives = await inspector.events(in: .objectives)
        XCTAssertEqual(objectives.map(\.kind), [.objectiveCreated])

        let memory = await inspector.events(in: .memory)
        XCTAssertEqual(memory.map(\.kind), [.memoryStored])

        let presence = await inspector.events(in: .presence)
        XCTAssertEqual(presence.map(\.kind), [.presenceOpportunity])
    }

    func testFailuresView() async {
        let inspector = AriaInspector()
        await inspector.ingest(sampleEvents())
        let failures = await inspector.failures()
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.source, "slack")
    }

    // MARK: - ReplayEngine (§56)

    func testStepReturnsPrefix() {
        let replay = ReplayEngine(sampleEvents())
        XCTAssertEqual(replay.step(to: 2).count, 3)
    }

    func testDiffReturnsRange() {
        let replay = ReplayEngine(sampleEvents())
        let between = replay.diff(from: 1, to: 3)
        XCTAssertEqual(between.count, 2)   // indices 2 and 3
    }

    func testExportIsNonEmpty() {
        let replay = ReplayEngine(sampleEvents())
        XCTAssertFalse(replay.export().isEmpty)
    }

    func testTimelineIsChronological() {
        let events = [
            AriaEvent(kind: .appOpened, source: "b", timestamp: Date(timeIntervalSince1970: 200)),
            AriaEvent(kind: .appOpened, source: "a", timestamp: Date(timeIntervalSince1970: 100)),
        ]
        let timeline = ReplayEngine(events).timeline()
        XCTAssertEqual(timeline.map(\.source), ["a", "b"])
    }
}
