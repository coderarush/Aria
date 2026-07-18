import Foundation

/// Drives the application boot flow (spec §8) and owns the root runtime
/// objects: the shared ``EventBus`` and the single ``AriaRuntime`` authority.
///
/// Spec §8 boot order is collapsed here into ``initialize()``; richer
/// `register` / `restore` / `recover` stages are layered on as the services
/// they coordinate come online.
actor AppBootstrapper {

    private(set) var eventBus: EventBus?
    private(set) var runtime: AriaRuntime?

    /// Stand up the event bus, construct the runtime on top of it, and start
    /// the runtime so it reaches `idle`. Returns the live runtime.
    @discardableResult
    func initialize() async -> AriaRuntime {
        let bus = EventBus()
        let runtime = AriaRuntime(eventBus: bus)
        await runtime.start()
        self.eventBus = bus
        self.runtime = runtime
        return runtime
    }

    /// True once the runtime has been initialized and reached `idle`.
    func verify() async -> Bool {
        guard let runtime else { return false }
        return await runtime.state == .idle
    }

    /// Full boot (spec §8): stand up the event bus, the runtime authority, and
    /// every core engine sharing that bus, then start the runtime. Returns the
    /// assembled ``RuntimeContainer``.
    func boot(flags: FeatureFlags = FeatureFlags()) async -> RuntimeContainer {
        let bus = EventBus()
        let runtime = AriaRuntime(eventBus: bus)
        await runtime.start()

        self.eventBus = bus
        self.runtime = runtime

        return RuntimeContainer(
            eventBus: bus,
            runtime: runtime,
            objectives: ObjectiveEngine(eventBus: bus),
            execution: ExecutionEngine(eventBus: bus),
            memory: MemoryStore(eventBus: bus),
            context: ContextCollector(eventBus: bus),
            presence: PresenceDetector(eventBus: bus),
            metrics: MetricsCollector(),
            timeline: ExecutionTimeline(),
            flags: flags)
    }
}
