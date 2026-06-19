import Foundation

/// The staged migration from the legacy path to the runtime (spec §51).
/// Default progression: legacy → shadow → dual → preferred → runtimeOnly →
/// cleanup. Every stage is reversible by setting the bridge back.
enum MigrationStage: String, Sendable, CaseIterable {
    case legacy       // runtime off; legacy serves
    case shadow       // legacy serves; runtime runs silently for comparison
    case dual         // both run; legacy serves; both exposed
    case preferred    // runtime serves, legacy is fallback
    case runtimeOnly  // runtime serves, legacy fallback only on failure
    case cleanup      // runtime only; legacy removed
}

/// A request to execute, abstracted away from either path's internals.
struct BridgeRequest: Sendable {
    let objective: String
    init(objective: String) { self.objective = objective }
}

/// A path's result.
struct BridgeResult: Sendable {
    let output: String
    let success: Bool
    let duration: TimeInterval
    init(output: String, success: Bool = true, duration: TimeInterval = 0) {
        self.output = output
        self.success = success
        self.duration = duration
    }
}

/// The existing production path (AgentOrchestrator/AriaController), wrapped
/// without modification (spec §51 LegacyAdapter — no direct deletions).
protocol LegacyExecutor: Sendable {
    func execute(_ request: BridgeRequest) async -> BridgeResult
}

/// The new runtime path.
protocol RuntimeExecutor: Sendable {
    func execute(_ request: BridgeRequest) async -> BridgeResult
}

/// A silent comparison of the two paths (spec §52).
struct ExecutionDiff: Sendable {
    let oldResult: String
    let newResult: String
    let oldDuration: TimeInterval
    let newDuration: TimeInterval
    let equal: Bool
    let confidence: Double
}

/// What the bridge ultimately served the user, and any shadow diff.
struct BridgeOutcome: Sendable {
    enum Source: String, Sendable { case legacy, runtime }
    let served: Source
    let output: String
    let diff: ExecutionDiff?
}

/// Routes execution between the legacy and runtime paths per ``MigrationStage``
/// (spec §51). Shadow/dual run the runtime silently and compare; preferred/
/// runtimeOnly serve the runtime with legacy fallback on failure. Never deletes
/// the legacy path — migration stays reversible by changing the stage.
actor RuntimeBridge {

    private(set) var stage: MigrationStage
    private let legacy: any LegacyExecutor
    private let runtime: any RuntimeExecutor
    private let eventBus: EventBus

    init(stage: MigrationStage,
         legacy: any LegacyExecutor,
         runtime: any RuntimeExecutor,
         eventBus: EventBus) {
        self.stage = stage
        self.legacy = legacy
        self.runtime = runtime
        self.eventBus = eventBus
    }

    func setStage(_ newStage: MigrationStage) { stage = newStage }

    func execute(_ request: BridgeRequest) async -> BridgeOutcome {
        switch stage {
        case .legacy:
            let result = await legacy.execute(request)
            return BridgeOutcome(served: .legacy, output: result.output, diff: nil)

        case .shadow, .dual:
            let legacyResult = await legacy.execute(request)
            let runtimeResult = await runtime.execute(request)
            let diff = makeDiff(legacyResult, runtimeResult)
            await eventBus.emit(AriaEvent(
                kind: .shadowCompared,
                source: "RuntimeBridge",
                payload: ["equal": String(diff.equal), "stage": stage.rawValue]))
            // User still sees the legacy result — shadow never affects them.
            return BridgeOutcome(served: .legacy, output: legacyResult.output, diff: diff)

        case .preferred, .runtimeOnly:
            let runtimeResult = await runtime.execute(request)
            if runtimeResult.success {
                return BridgeOutcome(served: .runtime, output: runtimeResult.output, diff: nil)
            }
            // Fallback keeps migration safe and reversible.
            let legacyResult = await legacy.execute(request)
            return BridgeOutcome(served: .legacy, output: legacyResult.output, diff: nil)

        case .cleanup:
            let result = await runtime.execute(request)
            return BridgeOutcome(served: .runtime, output: result.output, diff: nil)
        }
    }

    private func makeDiff(_ old: BridgeResult, _ new: BridgeResult) -> ExecutionDiff {
        let equal = old.output == new.output
        return ExecutionDiff(
            oldResult: old.output,
            newResult: new.output,
            oldDuration: old.duration,
            newDuration: new.duration,
            equal: equal,
            confidence: equal ? 1.0 : 0.0)
    }
}
