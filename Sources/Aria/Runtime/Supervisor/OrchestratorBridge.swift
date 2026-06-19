import Foundation

/// The single command-handling capability the bridge needs from the legacy
/// path. ``AgentOrchestrator`` already satisfies this shape, so it conforms via
/// an empty extension — no modification to the orchestrator (spec §51).
protocol CommandHandling: Sendable {
    func handle(command: String, privacyMode: Bool) async -> AriaResponse
}

extension AgentOrchestrator: CommandHandling {}

/// Adapts the production command handler (the real ``AgentOrchestrator``) to the
/// ``LegacyExecutor`` seam. Translates a ``BridgeRequest`` into a command and
/// the resulting ``AriaResponse`` into a ``BridgeResult``.
struct LegacyOrchestratorAdapter: LegacyExecutor {

    private let handler: any CommandHandling

    init(handler: any CommandHandling) {
        self.handler = handler
    }

    func execute(_ request: BridgeRequest) async -> BridgeResult {
        let response = await handler.handle(command: request.objective, privacyMode: false)
        return BridgeResult(output: response.message, success: response.succeeded)
    }
}

/// Adapts the new runtime path (``Coordinator``) to the ``RuntimeExecutor`` seam.
/// A `planner` maps the request objective to plan steps; until real tools are
/// ported to ``ExecutableTool`` the runtime side is exercised in shadow only.
struct RuntimeCoordinatorAdapter: RuntimeExecutor {

    private let coordinator: Coordinator
    private let planner: @Sendable (String) -> [PlanStep]
    private let rules: [String]

    init(coordinator: Coordinator,
         planner: @escaping @Sendable (String) -> [PlanStep],
         rules: [String]) {
        self.coordinator = coordinator
        self.planner = planner
        self.rules = rules
    }

    func execute(_ request: BridgeRequest) async -> BridgeResult {
        let objective = Domain.Objective(title: request.objective, intent: request.objective)
        let contract = await coordinator.run(objective: objective,
                                             steps: planner(request.objective),
                                             rules: rules)
        return BridgeResult(output: contract.status.rawValue,
                            success: contract.status == .completed)
    }
}

/// Builds a ``RuntimeBridge`` wired to the real orchestrator (legacy) and the
/// runtime coordinator. Defaults to ``MigrationStage/legacy`` so production
/// behavior is byte-identical until the migration is deliberately advanced.
enum OrchestratorBridge {
    static func make(legacyHandler: any CommandHandling,
                     runtime: any RuntimeExecutor,
                     eventBus: EventBus,
                     stage: MigrationStage = .legacy) -> RuntimeBridge {
        RuntimeBridge(stage: stage,
                      legacy: LegacyOrchestratorAdapter(handler: legacyHandler),
                      runtime: runtime,
                      eventBus: eventBus)
    }
}
