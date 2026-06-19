import Foundation

/// The outcome of executing a graph.
struct ExecutionReport: Sendable {
    var completed: [UUID]
    var failed: [UUID]
    var artifacts: [Domain.Artifact]

    /// A run succeeds when nothing failed.
    var success: Bool { failed.isEmpty }
}

/// Executes an ``ExecutionGraph`` of actions (spec §13).
///
/// Pipeline per action: dependency gate → supervised run (prepare/execute/
/// verify/cleanup with retry) → event emission → report aggregation. Runs in
/// dependency (topological) order; a cycle fails the whole graph. Parallel and
/// speculative modes build on the ready-set queries of ``ExecutionGraph`` and
/// are layered on in a later pass.
actor ExecutionEngine {

    private var tools: [String: any ExecutableTool] = [:]
    private let eventBus: EventBus
    private let supervisor: ExecutionSupervisor

    init(eventBus: EventBus, policy: ExecutionPolicy = ExecutionPolicy(), tools: [any ExecutableTool] = []) {
        self.eventBus = eventBus
        self.supervisor = ExecutionSupervisor(policy: policy)
        for tool in tools { self.tools[tool.name] = tool }
    }

    /// Register a tool under its ``ExecutableTool/name``.
    func register(_ tool: any ExecutableTool) {
        tools[tool.name] = tool
    }

    /// Execute the graph serially in dependency order, returning a report.
    func execute(_ graph: ExecutionGraph) async -> ExecutionReport {
        let order: [UUID]
        do {
            order = try graph.topologicalOrder()
        } catch {
            // A cyclic graph cannot be executed — everything fails.
            return ExecutionReport(completed: [], failed: Array(graph.nodes.keys), artifacts: [])
        }

        var completed: Set<UUID> = []
        var failed: [UUID] = []
        var artifacts: [Domain.Artifact] = []

        for id in order {
            guard let action = graph.nodes[id] else { continue }

            // Dependency gate: skip if any prerequisite failed.
            let deps = graph.dependencies[id] ?? []
            guard deps.isSubset(of: completed) else {
                failed.append(id)
                continue
            }

            guard let tool = tools[action.tool] else {
                failed.append(id)
                await eventBus.emit(AriaEvent(
                    kind: .taskStarted,
                    source: "ExecutionEngine",
                    payload: ["action": id.uuidString, "tool": action.tool, "error": "unregistered"],
                    priority: .high))
                continue
            }

            await eventBus.emit(AriaEvent(
                kind: .taskStarted,
                source: "ExecutionEngine",
                payload: ["action": id.uuidString, "tool": action.tool]))

            switch await supervisor.run(action, tool: tool) {
            case .success(let artifact):
                completed.insert(id)
                if let artifact { artifacts.append(artifact) }
                await eventBus.emit(AriaEvent(
                    kind: .toolExecuted,
                    source: action.tool,
                    payload: ["action": id.uuidString]))
                await eventBus.emit(AriaEvent(
                    kind: .verificationPassed,
                    source: "ExecutionEngine",
                    payload: ["action": id.uuidString]))
            case .failure:
                failed.append(id)
                await eventBus.emit(AriaEvent(
                    kind: .toolExecuted,
                    source: action.tool,
                    payload: ["action": id.uuidString, "result": "failed"],
                    priority: .high))
            }
        }

        return ExecutionReport(completed: Array(completed), failed: failed, artifacts: artifacts)
    }
}
