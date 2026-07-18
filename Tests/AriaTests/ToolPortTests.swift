import XCTest
@testable import Aria

private struct EchoTool: AriaTool {
    static let name = "echo"
    static let description = "echoes its msg input"
    func run(input: [String: String]) async throws -> ToolResult {
        .ok(input["msg"] ?? "empty")
    }
}

private struct FailingTool: AriaTool {
    static let name = "failing"
    static let description = "always fails"
    func run(input: [String: String]) async throws -> ToolResult { .fail("nope") }
}

private struct DangerTool: AriaTool {
    static let name = "danger"
    static let description = "destructive"
    var isDestructive: Bool { true }
    func run(input: [String: String]) async throws -> ToolResult { .ok("ran destructive") }
}

final class ToolPortTests: XCTestCase {

    func testAdapterNameFromStaticName() {
        let adapter = AriaToolAdapter(EchoTool())
        XCTAssertEqual(adapter.name, "echo")
    }

    func testAdapterRunsToolAndProducesArtifact() async {
        let bus = EventBus()
        let engine = ExecutionEngine(eventBus: bus, tools: [AriaToolAdapter(EchoTool())])
        var graph = ExecutionGraph()
        graph.addAction(Domain.Action(tool: "echo", parameters: ["msg": "hi"]))
        let report = await engine.execute(graph)
        XCTAssertTrue(report.success)
        XCTAssertEqual(report.artifacts.first?.reference, "hi")
    }

    func testAdapterFailureIsRecorded() async {
        let bus = EventBus()
        let engine = ExecutionEngine(eventBus: bus, tools: [AriaToolAdapter(FailingTool())])
        var graph = ExecutionGraph()
        graph.addAction(Domain.Action(tool: "failing"))
        let report = await engine.execute(graph)
        XCTAssertFalse(report.success)
    }

    func testDestructiveToolDeclinesOnRuntimePath() async {
        let bus = EventBus()
        let engine = ExecutionEngine(eventBus: bus, tools: [AriaToolAdapter(DangerTool())])
        var graph = ExecutionGraph()
        graph.addAction(Domain.Action(tool: "danger"))
        let report = await engine.execute(graph)
        XCTAssertFalse(report.success)   // declined, never run
    }

    func testRegisterAllFromRegistry() async {
        let bus = EventBus()
        let engine = ExecutionEngine(eventBus: bus)
        await engine.registerTools(from: ToolRegistry(tools: [EchoTool()]))
        var graph = ExecutionGraph()
        graph.addAction(Domain.Action(tool: "echo", parameters: ["msg": "registered"]))
        let report = await engine.execute(graph)
        XCTAssertTrue(report.success)
        XCTAssertEqual(report.artifacts.first?.reference, "registered")
    }
}
