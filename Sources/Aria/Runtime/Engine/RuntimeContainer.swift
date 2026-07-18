import Foundation

/// The wired-together runtime: every core engine sharing one ``EventBus``.
///
/// This is the dependency graph the spec's boot flow (§8) assembles — the
/// single object the rest of the app reaches through instead of constructing
/// engines ad hoc. All members are actors (or value types), so the container
/// is freely `Sendable`.
struct RuntimeContainer: Sendable {
    let eventBus: EventBus
    let runtime: AriaRuntime
    let objectives: ObjectiveEngine
    let execution: ExecutionEngine
    let memory: MemoryStore
    let context: ContextCollector
    let presence: PresenceDetector
    let metrics: MetricsCollector
    let timeline: ExecutionTimeline
    let flags: FeatureFlags
}
