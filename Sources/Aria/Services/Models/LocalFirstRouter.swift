import Foundation

/// A shared, non-queuing admission gate for local-model inference. When the
/// current runtime posture has no capacity left, callers use their existing
/// cloud fallback instead of stacking work on a thermally constrained Mac.
actor LocalWorkLimiter {
    static let shared = LocalWorkLimiter()

    private var activeRequests = 0

    func acquire(limit: Int) -> Bool {
        guard limit > 0, activeRequests < limit else { return false }
        activeRequests += 1
        return true
    }

    func release() {
        activeRequests = max(0, activeRequests - 1)
    }
}

/// Actor-isolated, model-specific availability cache for live local chat. A
/// runtime power cap can select a different model mid-session, so its probe must
/// never inherit an availability result from the larger model it replaced.
actor LocalChatAvailabilityCache {
    static let shared = LocalChatAvailabilityCache()

    private var probes: [String: (at: Date, alive: Bool)] = [:]

    func value(for model: String, now: Date = Date(), ttl: TimeInterval = 30) -> Bool? {
        guard let probe = probes[model] else { return nil }
        guard now.timeIntervalSince(probe.at) < ttl else {
            probes.removeValue(forKey: model)
            return nil
        }
        return probe.alive
    }

    func record(alive: Bool, model: String, at date: Date = Date()) {
        probes[model] = (at: date, alive: alive)
    }
}

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
    private let runtimeRecommendation: @Sendable () async -> RuntimeRecommendation
    private let chatProbeCache: LocalChatAvailabilityCache
    private let localWorkLimiter: LocalWorkLimiter

    init(defaults: UserDefaults = .standard,
         makeProvider: @escaping @Sendable (String) -> any ModelProvider = { OllamaProvider(model: $0) },
         availability: (@Sendable () async -> Bool)? = nil,
         runtimeRecommendation: @escaping @Sendable () async -> RuntimeRecommendation = {
             await RuntimeAdvisor.shared.refresh()
         },
         chatProbeCache: LocalChatAvailabilityCache = .shared,
         localWorkLimiter: LocalWorkLimiter = .shared) {
        self.defaults = defaults
        self.makeProvider = makeProvider
        self.availability = availability
        self.runtimeRecommendation = runtimeRecommendation
        self.chatProbeCache = chatProbeCache
        self.localWorkLimiter = localWorkLimiter
    }

    private var enabled: Bool { defaults.object(forKey: Self.toggleKey) as? Bool ?? true }   // local is the default (V9)
    var localModelName: String { defaults.string(forKey: Self.modelKey) ?? "" }

    static let chatModelKey = "app.localChatModel"
    /// Live voice chat can use an explicitly selected model; otherwise it follows
    /// the installed local model, with the runtime recommendation remaining a cap.
    var localChatModelName: String {
        let explicit = defaults.string(forKey: Self.chatModelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty { return explicit }
        let selected = localModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return selected.isEmpty ? OllamaProvider.defaultModel : selected
    }

    private func provider(model: String? = nil) -> any ModelProvider {
        makeProvider(model ?? localModelName)
    }

    /// The largest planning model that is appropriate right now. This is only a
    /// ceiling: a user's smaller selection is always preserved.
    func effectivePlanningModelName() async -> String {
        let selected = localModelName.isEmpty ? OllamaProvider.defaultModel : localModelName
        let runtime = await runtimeRecommendation()
        return RuntimePolicy.effectiveModel(selected: selected, cap: runtime.planningModelCap)
    }

    /// Voice favors the user's fast instruct model, capped by current power and
    /// thermal conditions without ever moving to a larger one.
    func effectiveChatModelName() async -> String {
        let runtime = await runtimeRecommendation()
        return RuntimePolicy.effectiveModel(selected: localChatModelName, cap: runtime.chatModelCap)
    }

    func permitsLocalPlanning() async -> Bool {
        guard enabled else { return false }
        return (await runtimeRecommendation()).permitsLocalPlanning
    }

    /// Reserve one local-inference slot for streaming chat or low-priority
    /// warming. Planning uses the same gate internally in `tryLocal`.
    func acquireLocalWorkSlot() async -> Bool {
        let runtime = await runtimeRecommendation()
        return await localWorkLimiter.acquire(limit: runtime.maxConcurrentLocalRequests)
    }

    func releaseLocalWorkSlot() async {
        await localWorkLimiter.release()
    }

    static let chatToggleKey = "app.localChat"

    /// Cheap "should LIVE CHAT go local right now?" — needs the master toggle,
    /// the separate chat opt-in, and a live server. Chat is opt-in (default
    /// off) because voice UX needs first-token in ~1s and full replies in
    /// seconds; measured on a 4B thinking model the full conversation payload
    /// runs minutes. Planner/agents/knowledge calls (short prompts) stay
    /// local by default — flip this on when running a faster instruct model.
    func chatGoesLocal() async -> Bool {
        // Local-first voice is ON by default; the availability probe below means it
        // only wins when a local server is actually alive, else cloud takes over.
        let chatOn = defaults.object(forKey: Self.chatToggleKey) as? Bool ?? true
        guard enabled, chatOn else { return false }
        let runtime = await runtimeRecommendation()
        guard runtime.permitsLocalChat else { return false }
        let model = RuntimePolicy.effectiveModel(
            selected: localChatModelName,
            cap: runtime.chatModelCap)
        if let cached = await chatProbeCache.value(for: model) { return cached }
        let alive = await provider(model: model).isAvailable()
        await chatProbeCache.record(alive: alive, model: model)
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
        let runtime = await runtimeRecommendation()
        guard runtime.permitsLocalPlanning else {
            return RoutingDecision(taskClass: taskClass, tier: .cloud, reason: runtime.reason)
        }
        let selected = localModelName.isEmpty ? OllamaProvider.defaultModel : localModelName
        let model = RuntimePolicy.effectiveModel(selected: selected, cap: runtime.planningModelCap)
        let alive: Bool
        if let availability {
            alive = await availability()
        } else {
            alive = await provider(model: model).isAvailable()
        }
        return RoutingPolicy.route(taskClass: taskClass,
                                   localFirstEnabled: true,
                                   localAvailable: alive)
    }

    /// Run the prompt on the local model. nil on any failure or empty output —
    /// the caller falls through to the cloud path, so local can never make Aria
    /// less capable than cloud-only. Outcomes feed LocalModelHealth (V11 P1).
    func tryLocal(prompt: String, temperature: Double) async -> String? {
        let runtime = await runtimeRecommendation()
        guard runtime.permitsLocalPlanning else { return nil }
        guard await localWorkLimiter.acquire(limit: runtime.maxConcurrentLocalRequests) else { return nil }
        let selected = localModelName.isEmpty ? OllamaProvider.defaultModel : localModelName
        let p = provider(model: RuntimePolicy.effectiveModel(selected: selected,
                                                              cap: runtime.planningModelCap))
        let started = Date()
        let output: String?
        do {
            let text = try await p.generateText(prompt: prompt, temperature: temperature)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await LocalModelHealth.shared.record(ok: false, latency: 0, error: "empty output")
                output = nil
            } else {
                await LocalModelHealth.shared.record(ok: true, latency: Date().timeIntervalSince(started))
                output = text
            }
        } catch {
            await LocalModelHealth.shared.record(ok: false, latency: 0,
                                                 error: String("\(error)".prefix(120)))
            output = nil
        }
        await localWorkLimiter.release()
        return output
    }
}
