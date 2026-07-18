import XCTest
@testable import Aria

final class LocalFirstRouterTests: XCTestCase {

    private static let configuredChatSentinel = "configured-chat-sentinel"
    private static let explicitChatSentinel = "explicit-chat-sentinel"

    private static let healthyRuntime = RuntimeRecommendation(
        posture: .balanced,
        permitsLocalPlanning: true,
        permitsLocalChat: true,
        maxConcurrentLocalRequests: 1,
        planningModelCap: "qwen3:8b",
        chatModelCap: "llama3.2:3b",
        reason: "Balanced for this Mac")

    private actor ProbeTracker {
        private var count = 0
        func probe() -> Bool { count += 1; return true }
        func hasProbed() -> Bool { count > 0 }
    }

    private final class ModelSelectionTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var models: [String] = []

        func record(_ model: String) {
            lock.lock()
            models.append(model)
            lock.unlock()
        }

        func lastModel() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return models.last
        }
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "lfr-\(UUID().uuidString)")!
    }

    func testChatProbeCacheIsModelSpecificAndExpires() async {
        let cache = LocalChatAvailabilityCache()
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        await cache.record(alive: true, model: "llama3.2:3b", at: now)

        let matching = await cache.value(for: "llama3.2:3b", now: now.addingTimeInterval(29))
        let differentModel = await cache.value(for: "llama3.2:1b", now: now.addingTimeInterval(1))
        let expired = await cache.value(for: "llama3.2:3b", now: now.addingTimeInterval(31))

        XCTAssertEqual(matching, true)
        XCTAssertNil(differentModel)
        XCTAssertNil(expired)
    }

    func testChatUsesConfiguredLocalModelWhenNoSeparateChatModelExists() async {
        let d = defaults()
        d.set(Self.configuredChatSentinel, forKey: "app.localModelName")
        let runtime = RuntimeRecommendation(
            posture: .balanced,
            permitsLocalPlanning: true,
            permitsLocalChat: true,
            maxConcurrentLocalRequests: 1,
            planningModelCap: "qwen3:4b",
            chatModelCap: "llama3.2:1b",
            reason: "Configured chat fallback test")
        let router = LocalFirstRouter(
            defaults: d,
            makeProvider: { _ in DeterministicProvider(script: [:], fallback: "local") },
            runtimeRecommendation: { runtime })
        let chatModel = await router.effectiveChatModelName()

        XCTAssertEqual(router.localChatModelName, Self.configuredChatSentinel)
        XCTAssertEqual(chatModel, Self.configuredChatSentinel)
    }

    func testExplicitChatModelTakesPrecedenceOverConfiguredLocalModel() async {
        let d = defaults()
        d.set(Self.configuredChatSentinel, forKey: "app.localModelName")
        d.set(Self.explicitChatSentinel, forKey: "app.localChatModel")
        let runtime = RuntimeRecommendation(
            posture: .balanced,
            permitsLocalPlanning: true,
            permitsLocalChat: true,
            maxConcurrentLocalRequests: 1,
            planningModelCap: "qwen3:4b",
            chatModelCap: "llama3.2:1b",
            reason: "Explicit chat precedence test")
        let router = LocalFirstRouter(
            defaults: d,
            makeProvider: { _ in DeterministicProvider(script: [:], fallback: "local") },
            runtimeRecommendation: { runtime })
        let chatModel = await router.effectiveChatModelName()

        XCTAssertEqual(router.localChatModelName, Self.explicitChatSentinel)
        XCTAssertEqual(chatModel, Self.explicitChatSentinel)
    }

    func testDisabledTogglesGoCloudWithoutProbing() async {
        let d = defaults()
        d.set(false, forKey: "app.localFirst")
        var probed = false
        let router = LocalFirstRouter(defaults: d,
                                      makeProvider: { _ in DeterministicProvider(script: [:], fallback: "x") },
                                      availability: { probed = true; return true },
                                      runtimeRecommendation: { Self.healthyRuntime })
        let decision = await router.decide(taskClass: .planning)
        XCTAssertEqual(decision.tier, .cloud)
        XCTAssertFalse(probed, "must not probe the local server when the toggle is off")
    }

    func testEnabledEligibleAndAvailableGoesLocal() async {
        let d = defaults()
        d.set(true, forKey: "app.localFirst")
        let router = LocalFirstRouter(defaults: d,
                                      makeProvider: { _ in DeterministicProvider(script: [:], fallback: "x") },
                                      availability: { true },
                                      runtimeRecommendation: { Self.healthyRuntime })
        let decision = await router.decide(taskClass: .planning)
        XCTAssertEqual(decision.tier, .local)
    }

    func testEnabledButDeadServerGoesCloud() async {
        let d = defaults()
        d.set(true, forKey: "app.localFirst")
        let router = LocalFirstRouter(defaults: d,
                                      makeProvider: { _ in DeterministicProvider(script: [:], fallback: "x") },
                                      availability: { false },
                                      runtimeRecommendation: { Self.healthyRuntime })
        let decision = await router.decide(taskClass: .planning)
        XCTAssertEqual(decision.tier, .cloud)
        XCTAssertTrue(decision.reason.contains("unreachable"))
    }

    func testTryLocalReturnsTextOnSuccess() async {
        let d = defaults()
        d.set(true, forKey: "app.localFirst")
        let router = LocalFirstRouter(
            defaults: d,
            makeProvider: { _ in DeterministicProvider(script: [:], fallback: "local says hi") },
            availability: { true },
            runtimeRecommendation: { Self.healthyRuntime })
        let out = await router.tryLocal(prompt: "plan something", temperature: 0.2)
        XCTAssertEqual(out, "local says hi")
    }

    func testTryLocalReturnsNilOnEmptyOutput() async {
        let d = defaults()
        d.set(true, forKey: "app.localFirst")
        let router = LocalFirstRouter(
            defaults: d,
            makeProvider: { _ in DeterministicProvider(script: [:], fallback: "") },
            availability: { true },
            runtimeRecommendation: { Self.healthyRuntime })
        let out = await router.tryLocal(prompt: "plan", temperature: 0.2)
        XCTAssertNil(out, "empty local output must fall through to cloud")
    }

    func testConstrainedRuntimeGoesCloudWithoutProbingProvider() async {
        let d = defaults()
        d.set(true, forKey: "app.localFirst")
        let tracker = ProbeTracker()
        let constrained = RuntimeRecommendation(
            posture: .constrained,
            permitsLocalPlanning: false,
            permitsLocalChat: false,
            maxConcurrentLocalRequests: 0,
            planningModelCap: nil,
            chatModelCap: nil,
            reason: "Mac is too warm for local work")
        let router = LocalFirstRouter(
            defaults: d,
            makeProvider: { _ in DeterministicProvider(script: [:], fallback: "unused") },
            availability: { await tracker.probe() },
            runtimeRecommendation: { constrained })

        let decision = await router.decide(taskClass: .planning)
        let didProbe = await tracker.hasProbed()

        XCTAssertEqual(decision.tier, .cloud)
        XCTAssertTrue(decision.reason.contains("too warm"))
        XCTAssertFalse(didProbe)
    }

    func testRuntimeCapsPlanningAndChatModelsWithoutUpscaling() async {
        let d = defaults()
        d.set("qwen3:14b", forKey: "app.localModelName")
        d.set("llama3.2:3b", forKey: "app.localChatModel")
        let batterySaver = RuntimeRecommendation(
            posture: .batterySaver,
            permitsLocalPlanning: true,
            permitsLocalChat: true,
            maxConcurrentLocalRequests: 1,
            planningModelCap: "qwen3:4b",
            chatModelCap: "llama3.2:1b",
            reason: "Preserving battery while keeping Aria local")
        let router = LocalFirstRouter(
            defaults: d,
            makeProvider: { _ in DeterministicProvider(script: [:], fallback: "unused") },
            runtimeRecommendation: { batterySaver })
        let planningModel = await router.effectivePlanningModelName()
        let chatModel = await router.effectiveChatModelName()

        XCTAssertEqual(planningModel, "qwen3:4b")
        XCTAssertEqual(chatModel, "llama3.2:1b")
    }

    func testPlanningAvailabilityProbesTheRuntimeCappedModel() async {
        let d = defaults()
        d.set(true, forKey: "app.localFirst")
        d.set("qwen3:14b", forKey: "app.localModelName")
        let tracker = ModelSelectionTracker()
        let batterySaver = RuntimeRecommendation(
            posture: .batterySaver,
            permitsLocalPlanning: true,
            permitsLocalChat: true,
            maxConcurrentLocalRequests: 1,
            planningModelCap: "qwen3:4b",
            chatModelCap: "llama3.2:1b",
            reason: "Preserving battery while keeping Aria local")
        let router = LocalFirstRouter(
            defaults: d,
            makeProvider: { model in
                tracker.record(model)
                return DeterministicProvider(script: [:], fallback: "unused")
            },
            runtimeRecommendation: { batterySaver })

        let decision = await router.decide(taskClass: .planning)

        XCTAssertEqual(decision.tier, .local)
        XCTAssertEqual(tracker.lastModel(), "qwen3:4b")
    }

    func testPlanningFallsBackWhenTheRuntimeCapacitySlotIsBusy() async {
        let d = defaults()
        d.set(true, forKey: "app.localFirst")
        let limiter = LocalWorkLimiter()
        let occupiesSlot = await limiter.acquire(limit: 1)
        XCTAssertTrue(occupiesSlot)
        defer { Task { await limiter.release() } }
        let router = LocalFirstRouter(
            defaults: d,
            makeProvider: { _ in DeterministicProvider(script: [:], fallback: "local response") },
            runtimeRecommendation: { Self.healthyRuntime },
            localWorkLimiter: limiter)

        let result = await router.tryLocal(prompt: "make a plan", temperature: 0)

        XCTAssertNil(result)
    }

    func testFailedPlanningAttemptReleasesItsCapacitySlot() async {
        let d = defaults()
        d.set(true, forKey: "app.localFirst")
        let limiter = LocalWorkLimiter()
        let router = LocalFirstRouter(
            defaults: d,
            makeProvider: { _ in DeterministicProvider(script: [:], fallback: "") },
            runtimeRecommendation: { Self.healthyRuntime },
            localWorkLimiter: limiter)

        let result = await router.tryLocal(prompt: "make a plan", temperature: 0)
        let nextRequestCanEnter = await limiter.acquire(limit: 1)

        XCTAssertNil(result)
        XCTAssertTrue(nextRequestCanEnter)
    }
}
