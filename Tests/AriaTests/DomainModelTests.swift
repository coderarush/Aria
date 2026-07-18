import XCTest
@testable import Aria

final class DomainModelTests: XCTestCase {

    // MARK: - Objective lifecycle (spec §7 states + functions)

    func testObjectiveStartsInCreated() {
        let objective = Domain.Objective(title: "Plan my week", intent: "plan")
        XCTAssertEqual(objective.status, .created)
    }

    func testObjectiveStartActivates() {
        var objective = Domain.Objective(title: "x", intent: "x")
        objective.start()
        XCTAssertEqual(objective.status, .active)
    }

    func testObjectivePauseResumeCycle() {
        var objective = Domain.Objective(title: "x", intent: "x")
        objective.start()
        objective.pause()
        XCTAssertEqual(objective.status, .paused)
        objective.resume()
        XCTAssertEqual(objective.status, .active)
    }

    func testObjectiveComplete() {
        var objective = Domain.Objective(title: "x", intent: "x")
        objective.start()
        objective.complete()
        XCTAssertEqual(objective.status, .completed)
    }

    func testObjectiveDefaults() {
        let objective = Domain.Objective(title: "x", intent: "x")
        XCTAssertEqual(objective.priority, .normal)
        XCTAssertEqual(objective.confidence, 0)
        XCTAssertTrue(objective.successCriteria.isEmpty)
    }

    // MARK: - Task status (spec §7)

    func testTaskStartsQueued() {
        let task = Domain.Task(objectiveID: UUID())
        XCTAssertEqual(task.status, .queued)
    }

    func testTaskTransitions() {
        var task = Domain.Task(objectiveID: UUID())
        task.status = .running
        XCTAssertEqual(task.status, .running)
        task.status = .complete
        XCTAssertEqual(task.status, .complete)
    }

    // MARK: - Action (spec §7)

    func testActionHoldsToolAndParameters() {
        let action = Domain.Action(tool: "gmail.send",
                                   parameters: ["to": "a@b.com"],
                                   permission: .requiresApproval)
        XCTAssertEqual(action.tool, "gmail.send")
        XCTAssertEqual(action.parameters["to"], "a@b.com")
        XCTAssertEqual(action.permission, .requiresApproval)
        XCTAssertEqual(action.status, .pending)
    }

    // MARK: - ContextSnapshot (spec §7)

    func testContextSnapshotCapturesReality() {
        let snapshot = Domain.ContextSnapshot(apps: ["Mail", "Safari"],
                                              clipboard: "hello",
                                              activity: "writing")
        XCTAssertEqual(snapshot.apps, ["Mail", "Safari"])
        XCTAssertEqual(snapshot.clipboard, "hello")
    }

    // MARK: - Memory expiry (spec §7)

    func testMemoryWithoutExpirationNeverExpires() {
        let memory = Domain.Memory(scope: .session, content: "x", source: "test")
        XCTAssertFalse(memory.isExpired(asOf: Date(timeIntervalSince1970: 10_000)))
    }

    func testMemoryExpiresAfterExpiration() {
        let expiry = Date(timeIntervalSince1970: 1_000)
        let memory = Domain.Memory(scope: .session, content: "x", source: "test",
                                   expiration: expiry)
        XCTAssertTrue(memory.isExpired(asOf: Date(timeIntervalSince1970: 2_000)))
        XCTAssertFalse(memory.isExpired(asOf: Date(timeIntervalSince1970: 500)))
    }
}
