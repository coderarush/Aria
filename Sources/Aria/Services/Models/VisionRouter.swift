import Foundation

/// Routes a single multimodal (image → text) call local-first, mirroring
/// `LocalFirstRouter` for text. Vision used to be Gemini-only (the computer-use
/// fallback + the Lens); this keeps Aria's promise of "on-device unless you opt
/// into cloud" honest for screen understanding too: when local-first is on AND a
/// vision-capable model is pulled (`app.localVisionModel`, e.g. `qwen2.5vl` /
/// `llava`) AND the Ollama server answers, the image never leaves the machine.
/// Cloud (Gemini) is the graceful fallback so the feature still works on day one.
enum VisionRouter {
    /// UserDefaults key naming the local vision model to use. Empty ⇒ no local
    /// vision configured ⇒ always cloud.
    static let modelKey = "app.localVisionModel"

    static func localModelName(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: modelKey)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// Local-first master toggle (shared with text routing; default ON).
    static func localFirstEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: LocalFirstRouter.toggleKey) as? Bool ?? true
    }

    /// Whether a local vision call would actually run right now: master toggle on,
    /// a model configured, and the server reachable.
    static func localAvailable(defaults: UserDefaults = .standard,
                               makeProvider: (String) -> OllamaProvider = { OllamaProvider(model: $0) }) async -> Bool {
        let name = localModelName(defaults: defaults)
        guard localFirstEnabled(defaults: defaults), !name.isEmpty else { return false }
        return await makeProvider(name).isAvailable()
    }

    /// Explain/describe an image. Tries local vision first when available, then
    /// falls back to Gemini. Returns nil only when BOTH paths fail (no local
    /// model + no/empty cloud reply), so callers can show a clean "couldn't see
    /// that" message instead of a spinner that never ends.
    static func explain(prompt: String,
                        jpeg: Data,
                        temperature: Double = 0.1,
                        defaults: UserDefaults = .standard,
                        gemini: GeminiClient = GeminiClient(),
                        makeProvider: (String) -> OllamaProvider = { OllamaProvider(model: $0) }) async -> String? {
        let name = localModelName(defaults: defaults)
        if localFirstEnabled(defaults: defaults), !name.isEmpty {
            let local = makeProvider(name)
            if await local.isAvailable(),
               let text = try? await local.generateTextWithImage(prompt: prompt, jpeg: jpeg, temperature: temperature),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await RoutingLog.shared.record(RoutingDecision(taskClass: .vision, tier: .local, reason: "local vision (\(name))"))
                return text
            }
            await RoutingLog.shared.record(RoutingDecision(taskClass: .vision, tier: .cloud, reason: "local vision unavailable → Gemini"))
        }
        let cloud = (try? await gemini.generateTextWithImage(prompt: prompt, jpeg: jpeg, temperature: temperature)) ?? ""
        return cloud.isEmpty ? nil : cloud
    }
}
