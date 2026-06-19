import Foundation

/// Provider abstraction (V9 constitution: "the rest of Aria must remain
/// provider-agnostic; providers should be replaceable"). Phase B scope is plain
/// text generation — the seam every planner/agent/synthesis call goes through.
/// Streaming function-calling (the live conversation path) stays on the proven
/// Gemini pipeline and migrates behind this protocol in a later phase.
protocol ModelProvider: Sendable {
    /// Stable identifier, used in logs and routing decisions.
    var id: String { get }
    /// Cheap health probe — a dead provider must answer false fast, never hang.
    func isAvailable() async -> Bool
    func generateText(prompt: String, temperature: Double) async throws -> String
}

/// Scripted provider for demos and tests (the engine behind ARIA_DEMO_MODE):
/// deterministic, repeatable, never fails during a recording. Matches the first
/// script key contained in the prompt (case-insensitive), else the fallback line.
actor DeterministicProvider: ModelProvider {
    nonisolated let id = "deterministic"

    private let script: [String: String]
    private let fallback: String
    private var prompts: [String] = []

    init(script: [String: String], fallback: String) {
        self.script = script
        self.fallback = fallback
    }

    func isAvailable() async -> Bool { true }

    func generateText(prompt: String, temperature: Double) async throws -> String {
        prompts.append(prompt)
        let lower = prompt.lowercased()
        // Sorted for determinism when multiple keys match.
        for key in script.keys.sorted() where lower.contains(key.lowercased()) {
            return script[key]!
        }
        return fallback
    }

    /// Every prompt seen, in order — lets demo scripts and tests assert flow.
    func transcript() -> [String] { prompts }
}
