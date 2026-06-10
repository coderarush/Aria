import Foundation

/// Decides, per call, whether a local-eligible piece of work should run on the
/// local model — and runs it there when so. Used by `GeminiClient.generateText`
/// as an opt-in pre-step: the master toggle defaults OFF, so cloud behavior is
/// untouched until the user enables local-first in Settings.
///
/// Reads UserDefaults directly (no MainActor hop — same pattern as the fallback
/// chain). Every decision lands in `RoutingLog` for the router dashboard.
struct LocalFirstRouter {
    static let toggleKey = "app.localFirst"
    static let modelKey = "app.localModelName"

    private let defaults: UserDefaults
    private let makeProvider: @Sendable (String) -> any ModelProvider
    private let availability: (@Sendable () async -> Bool)?

    init(defaults: UserDefaults = .standard,
         makeProvider: @escaping @Sendable (String) -> any ModelProvider = { OllamaProvider(model: $0) },
         availability: (@Sendable () async -> Bool)? = nil) {
        self.defaults = defaults
        self.makeProvider = makeProvider
        self.availability = availability
    }

    private var enabled: Bool { defaults.bool(forKey: Self.toggleKey) }
    private var modelName: String { defaults.string(forKey: Self.modelKey) ?? "" }

    private func provider() -> any ModelProvider { makeProvider(modelName) }

    /// Routing decision for this task class right now. Skips the availability
    /// probe entirely when the toggle is off or the class is cloud-bound.
    func decide(taskClass: TaskClass) async -> RoutingDecision {
        guard enabled, RoutingPolicy.localEligible.contains(taskClass) else {
            return RoutingPolicy.route(taskClass: taskClass,
                                       localFirstEnabled: enabled,
                                       localAvailable: false)
        }
        let alive: Bool
        if let availability {
            alive = await availability()
        } else {
            alive = await provider().isAvailable()
        }
        return RoutingPolicy.route(taskClass: taskClass,
                                   localFirstEnabled: true,
                                   localAvailable: alive)
    }

    /// Run the prompt on the local model. nil on any failure or empty output —
    /// the caller falls through to the cloud path, so local can never make Aria
    /// less capable than cloud-only.
    func tryLocal(prompt: String, temperature: Double) async -> String? {
        let p = provider()
        guard let text = try? await p.generateText(prompt: prompt, temperature: temperature),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }
}
