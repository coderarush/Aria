import Foundation

/// Builds the ordered list of fallback providers Aria tries when the Gemini free tier
/// is exhausted. Fast, free clouds first (Groq → Cerebras → OpenRouter), then a local
/// Ollama server if the user enabled it. Each is included only when it has a key (or,
/// for local, when enabled), so the chain is exactly what the user has configured.
enum ProviderConfig {
    static func fallbacks(includeLocal: Bool, localModel: String) -> [OpenAICompatibleClient] {
        var list: [OpenAICompatibleClient] = [
            OpenAICompatibleClient(
                label: "Groq",
                baseURL: "https://api.groq.com/openai/v1",
                models: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"],
                keyProvider: { KeychainManager.read(account: KeychainKey.groqAPIKey) }),
            OpenAICompatibleClient(
                label: "Cerebras",
                baseURL: "https://api.cerebras.ai/v1",
                models: ["llama-3.3-70b", "llama3.1-8b"],
                keyProvider: { KeychainManager.read(account: KeychainKey.cerebrasAPIKey) }),
            OpenAICompatibleClient(
                label: "OpenRouter",
                baseURL: "https://openrouter.ai/api/v1",
                models: ["meta-llama/llama-3.3-70b-instruct:free", "google/gemma-2-9b-it:free"],
                keyProvider: { KeychainManager.read(account: KeychainKey.openRouterAPIKey) })
        ]
        if includeLocal {
            list.append(OpenAICompatibleClient(
                label: "Local",
                baseURL: "http://localhost:11434/v1",   // Ollama's OpenAI-compatible endpoint
                models: [localModel.isEmpty ? OllamaProvider.defaultModel : localModel],
                keyProvider: { nil },
                requiresKey: false))
        }
        return list
    }

    /// Concise persona for local + fallback providers (Gemini's own prompt stays as is).
    static var chatSystemPrompt: String {
        """
        You are Aria, a confident, charming, concise voice assistant on the user's Mac. \
        Answer naturally and briefly, like a spoken reply. Use a tool when the user wants \
        an action taken; otherwise just answer. Never mention tools or internal plumbing.
        """ + PersonaStyle.current.promptSuffix
    }
}
