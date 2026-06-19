import Foundation

/// Cloud tier behind the provider seam: wraps the proven `GeminiClient`
/// (rotation, pacing, fallback chain intact — wrap, don't rewrite). Exists so
/// consumers and future phases can hold `any ModelProvider` without caring
/// which side of the local/cloud line answers.
struct GeminiProvider: ModelProvider {
    let id = "cloud-gemini"
    private let client: GeminiClient

    init(client: GeminiClient = GeminiClient()) {
        self.client = client
    }

    /// Gemini availability is governed by keys + quota inside the client itself;
    /// from the routing seam it is always worth attempting.
    func isAvailable() async -> Bool { true }

    func generateText(prompt: String, temperature: Double) async throws -> String {
        try await client.generateText(prompt: prompt, temperature: temperature)
    }
}
