import Foundation

/// Adapts a legacy ``AriaTool`` to the runtime ``ExecutableTool`` seam so the
/// new execution path can run the real tools.
///
/// Mapping: ``Domain/Action`` parameters → `run(input:)`; a successful
/// ``ToolResult`` becomes an artifact, a failure throws so the supervisor
/// records it. `@unchecked Sendable` because tools predate Sendability and run
/// serialized through the actor-isolated ``ExecutionEngine``.
///
/// SAFETY: destructive tools are declined here — the runtime path has no
/// confirmation gate wired yet, and approvals must never be silently removed
/// (spec §106). They will run only once PermissionOS/confirmation is wired in.
struct AriaToolAdapter: ExecutableTool, @unchecked Sendable {

    let name: String
    private let destructive: Bool
    private let wrapped: any AriaTool

    init(_ tool: any AriaTool) {
        self.wrapped = tool
        self.name = type(of: tool).name
        self.destructive = tool.isDestructive
    }

    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? {
        if destructive {
            throw ToolError.executionFailed("requires approval (no gate on runtime path): \(name)")
        }
        let result = try await wrapped.run(input: action.parameters)
        guard result.success else {
            throw ToolError.executionFailed(result.output)
        }
        return Domain.Artifact(kind: .other, reference: result.output)
    }

    /// Wrap a list of legacy tools as adapters.
    static func adapters(from tools: [any AriaTool]) -> [AriaToolAdapter] {
        tools.map(AriaToolAdapter.init)
    }
}

extension ExecutionEngine {
    /// Register every tool from a ``ToolRegistry`` onto this engine.
    func registerTools(from registry: ToolRegistry) async {
        for name in await registry.allNames() {
            if let tool = await registry.tool(named: name) {
                register(AriaToolAdapter(tool))
            }
        }
    }
}
