import Foundation

/// Bounded, transparent store of observations (spec §70/§83). Every entry is
/// visible, queryable, and deletable; retention is capped (ephemeral-first).
actor PerceptionStore {

    private var observations: [Observation] = []
    private let maxRetained: Int

    init(maxRetained: Int = 512) {
        self.maxRetained = max(0, maxRetained)
    }

    func store(_ observation: Observation) {
        observations.append(observation)
        if observations.count > maxRetained {
            observations.removeFirst(observations.count - maxRetained)
        }
    }

    func all(source: String? = nil, tag: String? = nil) -> [Observation] {
        observations.filter { observation in
            (source == nil || observation.source == source)
                && (tag == nil || observation.tags.contains(tag!))
        }
    }

    /// Delete a single observation (spec §83 deletable).
    func delete(_ id: UUID) {
        observations.removeAll { $0.id == id }
    }

    func clear() { observations.removeAll() }
}
