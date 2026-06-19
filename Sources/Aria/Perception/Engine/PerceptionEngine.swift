import Foundation

/// The Perception OS (spec §70). Pipeline: observe → normalize → understand →
/// publish → store (spec §69). It NEVER executes — perception only produces
/// observations for presence and memory to consume.
actor PerceptionEngine {

    private let bus: ObservationBus
    private let store: PerceptionStore
    private let policy: ObservationPolicy

    init(bus: ObservationBus, store: PerceptionStore, policy: ObservationPolicy = ObservationPolicy()) {
        self.bus = bus
        self.store = store
        self.policy = policy
    }

    /// Ingest an observation: admit it through the policy, store and publish it.
    /// Returns whether it was admitted (filtered observations are dropped).
    @discardableResult
    func ingest(_ observation: Observation) async -> Bool {
        guard policy.admits(observation) else { return false }
        await store.store(observation)
        await bus.publish(observation)
        return true
    }

    func recent(source: String? = nil, tag: String? = nil) async -> [Observation] {
        await store.all(source: source, tag: tag)
    }
}
