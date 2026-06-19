import Foundation

/// In-memory store of ``Domain/Memory`` (spec §7 / §18 memory layer).
///
/// Owns persisted understanding, filters by scope, and prunes expired entries.
/// Emits `memoryStored` so the rest of the runtime can react. A durable
/// SQLite-backed implementation conforms to the same surface later (Wave 8).
actor MemoryStore {

    private var memories: [UUID: Domain.Memory] = [:]
    private let eventBus: EventBus

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    func store(_ memory: Domain.Memory) async {
        memories[memory.id] = memory
        await eventBus.emit(AriaEvent(
            kind: .memoryStored,
            source: "MemoryStore",
            payload: ["id": memory.id.uuidString, "scope": memory.scope.rawValue]))
    }

    func get(_ id: UUID) -> Domain.Memory? { memories[id] }

    /// All stored memories, optionally filtered to a single scope.
    func all(scope: Domain.Memory.Scope? = nil) -> [Domain.Memory] {
        let values = Array(memories.values)
        guard let scope else { return values }
        return values.filter { $0.scope == scope }
    }

    /// Remove every memory expired as of `date`; returns how many were removed.
    @discardableResult
    func pruneExpired(asOf date: Date) -> Int {
        let expired = memories.filter { $0.value.isExpired(asOf: date) }
        for id in expired.keys { memories[id] = nil }
        return expired.count
    }
}
