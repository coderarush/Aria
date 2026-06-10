import Foundation

/// The local tier: an Ollama server on localhost speaking the OpenAI-compatible
/// API. Qwen 3 8B is the constitution's default local target (execution-first:
/// tool use, planning, structured output). MLX can replace this runtime later
/// behind the same `ModelProvider` protocol without touching any consumer.
///
/// Generation reuses the proven `OpenAICompatibleClient` transport; this type
/// adds identity, the model default, and a fast availability probe so routing
/// can fall back to cloud instantly when no local server is running.
struct OllamaProvider: ModelProvider {
    static let defaultModel = "qwen3:8b"
    static let baseURL = "http://localhost:11434/v1"

    let id = "local-ollama"
    let model: String
    private let probe: @Sendable () async -> Bool
    private let client: OpenAICompatibleClient

    init(model: String = OllamaProvider.defaultModel,
         probe: (@Sendable () async -> Bool)? = nil) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? Self.defaultModel : trimmed
        self.model = resolved
        self.probe = probe ?? Self.defaultProbe
        self.client = OpenAICompatibleClient(
            label: "Ollama",
            baseURL: Self.baseURL,
            models: [resolved],
            keyProvider: { nil },
            requiresKey: false)
    }

    func isAvailable() async -> Bool { await probe() }

    func generateText(prompt: String, temperature: Double) async throws -> String {
        try await client.generateText(prompt: prompt, temperature: temperature)
    }

    /// 1.5s HEAD-style probe against Ollama's tag listing. Dead server → false
    /// fast; routing then goes cloud without the user noticing.
    private static let defaultProbe: @Sendable () async -> Bool = {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
