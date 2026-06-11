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

    private var enabled: Bool { defaults.object(forKey: Self.toggleKey) as? Bool ?? true }   // local is the default (V9)
    var localModelName: String { defaults.string(forKey: Self.modelKey) ?? "" }

    private func provider() -> any ModelProvider { makeProvider(localModelName) }

    // Cached availability so the live conversation path never pays the 1.5s
    // dead-server probe per turn. 30s TTL; guarded for cross-task access.
    private static let probeLock = NSLock()
    nonisolated(unsafe) private static var lastProbe: (at: Date, alive: Bool)?

    static let chatToggleKey = "app.localChat"

    /// Cheap "should LIVE CHAT go local right now?" — needs the master toggle,
    /// the separate chat opt-in, and a live server. Chat is opt-in (default
    /// off) because voice UX needs first-token in ~1s and full replies in
    /// seconds; measured on a 4B thinking model the full conversation payload
    /// runs minutes. Planner/agents/knowledge calls (short prompts) stay
    /// local by default — flip this on when running a faster instruct model.
    func chatGoesLocal() async -> Bool {
        guard enabled, defaults.bool(forKey: Self.chatToggleKey) else { return false }
        Self.probeLock.lock()
        if let p = Self.lastProbe, Date().timeIntervalSince(p.at) < 30 {
            Self.probeLock.unlock()
            return p.alive
        }
        Self.probeLock.unlock()
        let alive = await provider().isAvailable()
        Self.probeLock.lock()
        Self.lastProbe = (Date(), alive)
        Self.probeLock.unlock()
        return alive
    }

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
    /// less capable than cloud-only. Outcomes feed LocalModelHealth (V11 P1).
    func tryLocal(prompt: String, temperature: Double) async -> String? {
        let p = provider()
        let started = Date()
        do {
            let text = try await p.generateText(prompt: prompt, temperature: temperature)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await LocalModelHealth.shared.record(ok: false, latency: 0, error: "empty output")
                return nil
            }
            await LocalModelHealth.shared.record(ok: true, latency: Date().timeIntervalSince(started))
            return text
        } catch {
            await LocalModelHealth.shared.record(ok: false, latency: 0,
                                                 error: String("\(error)".prefix(120)))
            return nil
        }
    }
}
