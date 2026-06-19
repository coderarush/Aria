import XCTest
@testable import Aria

final class Part2ContinuityTests: XCTestCase {

    func testCheckpointStoresAndIsLatestAndEmits() async {
        let bus = EventBus()
        let engine = ContinuityEngine(eventBus: bus)
        let objective = UUID()
        let checkpoint = await engine.checkpoint(objectiveID: objective, kind: .milestone,
                                                 tools: ["gmail"], state: .executing)

        let restored = await engine.restore(checkpoint.id)
        XCTAssertEqual(restored?.id, checkpoint.id)
        XCTAssertEqual(restored?.tools, ["gmail"])

        let kinds = await bus.replay().map(\.kind)
        XCTAssertTrue(kinds.contains(.checkpointSaved))
    }

    func testResumeLatestReturnsMostRecent() async {
        let engine = ContinuityEngine(eventBus: EventBus())
        _ = await engine.checkpoint(objectiveID: UUID())
        let second = await engine.checkpoint(objectiveID: UUID())
        let resumed = await engine.resumeLatest()
        XCTAssertEqual(resumed?.id, second.id)
    }

    func testResumeByObjectiveFilters() async {
        let engine = ContinuityEngine(eventBus: EventBus())
        let a = UUID(), b = UUID()
        _ = await engine.checkpoint(objectiveID: a)
        _ = await engine.checkpoint(objectiveID: b)
        let resumedA = await engine.resume(objective: a)
        XCTAssertEqual(resumedA?.objectiveID, a)
    }

    func testPauseCreatesAutomaticCheckpoint() async {
        let engine = ContinuityEngine(eventBus: EventBus())
        let objective = UUID()
        let checkpoint = await engine.pause(objectiveID: objective)
        XCTAssertEqual(checkpoint.kind, .automatic)
        XCTAssertEqual(checkpoint.state, RuntimeState.paused.rawValue)
        XCTAssertEqual(checkpoint.objectiveID, objective)
    }

    func testBranchCopiesWithNewIdentity() async {
        let engine = ContinuityEngine(eventBus: EventBus())
        let objective = UUID()
        let output = UUID()
        let original = await engine.checkpoint(objectiveID: objective, outputs: [output])
        let branched = await engine.branch(from: original.id)
        XCTAssertNotNil(branched)
        XCTAssertNotEqual(branched?.id, original.id)
        XCTAssertEqual(branched?.objectiveID, objective)
        XCTAssertEqual(branched?.outputs, [output])
    }

    func testRestoreUnknownReturnsNil() async {
        let engine = ContinuityEngine(eventBus: EventBus())
        let restored = await engine.restore(UUID())
        XCTAssertNil(restored)
    }
}
