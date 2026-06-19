import XCTest
@testable import Aria

// MARK: - Test doubles

private actor CallLog {
    private(set) var executed: [String] = []
    private(set) var attempts = 0
    func record(_ name: String) { executed.append(name) }
    func bumpAttempt() -> Int { attempts += 1; return attempts }
    func snapshotExecuted() -> [String] { executed }
    func snapshotAttempts() -> Int { attempts }
}

private struct RecordingTool: ExecutableTool {
    let name: String
    let log: CallLog
    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? {
        await log.record(name)
        return Domain.Artifact(kind: .other, reference: name)
    }
}

private struct FlakyTool: ExecutableTool {
    let name: String
    let failTimes: Int
    let log: CallLog
    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? {
        let attempt = await log.bumpAttempt()
        if attempt <= failTimes { throw NSError(domain: "flaky", code: attempt) }
        return Domain.Artifact(kind: .other, reference: name)
    }
}

private struct AlwaysFailTool: ExecutableTool {
    let name: String
    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? {
        throw NSError(domain: "always", code: 1)
    }
}

final class ExecutionEngineTests: XCTestCase {

    func testExecutesActionViaRegisteredTool() async {
        let log = CallLog()
        let engine = ExecutionEngine(eventBus: EventBus())
        await engine.register(RecordingTool(name: "t", log: log))

        var graph = ExecutionGraph()
        graph.addAction(Domain.Action(tool: "t"))

        let report = await engine.execute(graph)
        let executed = await log.snapshotExecuted()
        XCTAssertTrue(report.success)
        XCTAssertEqual(executed, ["t"])
        XCTAssertEqual(report.artifacts.count, 1)
    }

    func testRespectsDependencyOrder() async {
        let log = CallLog()
        let engine = ExecutionEngine(eventBus: EventBus())
        await engine.register(RecordingTool(name: "a", log: log))
        await engine.register(RecordingTool(name: "b", log: log))

        var graph = ExecutionGraph()
        let a = Domain.Action(tool: "a")
        let b = Domain.Action(tool: "b")
        graph.addAction(a)
        graph.addAction(b, dependsOn: [a.id])

        let report = await engine.execute(graph)
        let executed = await log.snapshotExecuted()
        XCTAssertTrue(report.success)
        XCTAssertEqual(executed, ["a", "b"])
    }

    func testRetriesFlakyActionUntilSuccess() async {
        let log = CallLog()
        let engine = ExecutionEngine(eventBus: EventBus(),
                                     policy: ExecutionPolicy(maxRetries: 2))
        await engine.register(FlakyTool(name: "f", failTimes: 2, log: log))

        var graph = ExecutionGraph()
        graph.addAction(Domain.Action(tool: "f"))

        let report = await engine.execute(graph)
        let attempts = await log.snapshotAttempts()
        XCTAssertTrue(report.success)
        XCTAssertEqual(attempts, 3)
    }

    func testReportsFailureWhenRetriesExhausted() async {
        let engine = ExecutionEngine(eventBus: EventBus(),
                                     policy: ExecutionPolicy(maxRetries: 1))
        await engine.register(AlwaysFailTool(name: "x"))

        var graph = ExecutionGraph()
        let action = Domain.Action(tool: "x")
        graph.addAction(action)

        let report = await engine.execute(graph)
        XCTAssertFalse(report.success)
        XCTAssertEqual(report.failed, [action.id])
    }

    func testUnregisteredToolFails() async {
        let engine = ExecutionEngine(eventBus: EventBus())
        var graph = ExecutionGraph()
        graph.addAction(Domain.Action(tool: "ghost"))

        let report = await engine.execute(graph)
        XCTAssertFalse(report.success)
    }

    func testEmitsExecutionEvents() async {
        let bus = EventBus()
        let engine = ExecutionEngine(eventBus: bus)
        await engine.register(RecordingTool(name: "t", log: CallLog()))

        var graph = ExecutionGraph()
        graph.addAction(Domain.Action(tool: "t"))
        _ = await engine.execute(graph)

        let kinds = await bus.replay().map(\.kind)
        XCTAssertTrue(kinds.contains(.taskStarted))
        XCTAssertTrue(kinds.contains(.toolExecuted))
        XCTAssertTrue(kinds.contains(.verificationPassed))
    }
}
