import Foundation

/// A sub-agent runs a multi-step task on Aria's behalf. The orb shows the
/// `.acting` state (orblets) while one or more sub-agents run.
protocol SubAgent {
    var name: String { get }
    var description: String { get }
    /// One-line flavor text used in narration and the crew roster.
    var persona: String { get }
    /// Tool names this agent may call. Empty means no restriction.
    var allowedTools: [String] { get }
    func execute(task: String, context: AgentContext) async -> AgentResult
}

extension SubAgent {
    var persona: String { "" }
    var allowedTools: [String] { [] }
}

/// Everything a sub-agent needs: the model, the tool registry, the dynamic
/// factory, system context, and a way to run a single tool action through the
/// orchestrator (so sub-agents reuse confirmation + native/dynamic routing).
struct AgentContext {
    let gemini: GeminiClient
    let registry: ToolRegistry
    let factory: DynamicToolFactory
    let system: GeminiClient.SystemContext
    /// Run one action (output of prior step passed along) and get its result.
    let runAction: @Sendable (AgentAction, String) async -> ToolResult
}

struct AgentResult: Equatable {
    let success: Bool
    let output: String
    /// Paths to any files the sub-agent produced.
    let artifacts: [String]

    init(success: Bool, output: String, artifacts: [String] = []) {
        self.success = success
        self.output = output
        self.artifacts = artifacts
    }

    static func ok(_ output: String, artifacts: [String] = []) -> AgentResult {
        AgentResult(success: true, output: output, artifacts: artifacts)
    }
    static func fail(_ output: String) -> AgentResult {
        AgentResult(success: false, output: output)
    }
}

/// Scope enforcement for sub-agent tool use. An agent's `allowedTools` is a
/// hard allowlist (empty = unrestricted, per the protocol contract); the
/// orchestrator consults this before running any action an agent requests, so
/// a confused or manipulated model can't route e.g. `shell` through a
/// web-research agent.
enum SubAgentPolicy {
    static func permits(allowedTools: [String], tool: String) -> Bool {
        allowedTools.isEmpty || allowedTools.contains(tool)
    }
}

/// Registry of available sub-agents, keyed by `name`.
actor SubAgentRegistry {
    private var agents: [String: SubAgent] = [:]

    init(agents: [SubAgent] = SubAgentRegistry.builtins()) {
        for agent in agents { self.agents[agent.name] = agent }
    }

    func agent(named name: String) -> SubAgent? { agents[name] }
    func contains(_ name: String) -> Bool { agents[name] != nil }
    func catalog() -> String {
        agents.values
            .map { "- \($0.name): \($0.description)" }
            .sorted()
            .joined(separator: "\n")
    }

    /// Returns a sorted roster of the live crew (name, persona, description).
    func crew() -> [(name: String, persona: String, description: String)] {
        agents.values
            .map { ($0.name, $0.persona, $0.description) }
            .sorted { $0.name < $1.name }
    }

    /// Nonisolated static variant — builds from builtins without touching actor state.
    nonisolated static func crewInfo() -> [(name: String, persona: String, description: String)] {
        builtins()
            .map { ($0.name, $0.persona, $0.description) }
            .sorted { $0.name < $1.name }
    }

    static func builtins() -> [SubAgent] {
        [ResearchAgent(), LyraAgent(), CodeWriterAgent(), CometAgent(), TaskPlannerAgent(), PilotAgent()]
    }
}
