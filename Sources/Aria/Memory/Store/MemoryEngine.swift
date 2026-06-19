import Foundation

/// The Memory Operating System (spec §27): stores, ranks, expires, and merges
/// ``MemoryRecord`` values. Store is gated by importance so only records at or
/// above the scorer's threshold are kept. Emits `memoryStored` on accept.
///
/// Built additively over the Part 1 event bus; the simpler ``MemoryStore`` is
/// left intact.
actor MemoryEngine {

    private var records: [UUID: MemoryRecord] = [:]
    private let eventBus: EventBus
    private let scorer: ImportanceScorer

    init(eventBus: EventBus, scorer: ImportanceScorer = ImportanceScorer()) {
        self.eventBus = eventBus
        self.scorer = scorer
    }

    /// Store a record if its importance clears the threshold. Returns whether
    /// it was kept.
    @discardableResult
    func store(_ record: MemoryRecord) async -> Bool {
        guard record.importance >= scorer.threshold else { return false }
        records[record.id] = record
        await eventBus.emit(AriaEvent(
            kind: .memoryStored,
            source: "MemoryEngine",
            payload: ["id": record.id.uuidString, "type": record.type.rawValue]))
        return true
    }

    func get(_ id: UUID) -> MemoryRecord? { records[id] }

    func all(type: MemoryRecord.MemoryType? = nil) -> [MemoryRecord] {
        let values = Array(records.values)
        guard let type else { return values }
        return values.filter { $0.type == type }
    }

    /// Drop every record expired as of `date`; returns the count removed.
    @discardableResult
    func expire(asOf date: Date) -> Int {
        let expired = records.filter { $0.value.isExpired(asOf: date) }
        for id in expired.keys { records[id] = nil }
        return expired.count
    }

    /// Fold one record's signals into another (spec §27 merge): keeps the
    /// stronger importance/confidence and unions artifacts.
    func merge(_ source: UUID, into target: UUID) {
        guard let from = records[source], var into = records[target] else { return }
        into.importance = max(into.importance, from.importance)
        into.confidence = max(into.confidence, from.confidence)
        into.artifacts = Array(Set(into.artifacts + from.artifacts))
        records[target] = into
        records[source] = nil
    }
}
