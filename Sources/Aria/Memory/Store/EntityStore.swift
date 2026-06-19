import Foundation

/// "Aria has a model of YOU." The Entity Store holds Aria's on-device entity
/// graph — the people, projects, places, and things you refer to — so casual
/// references in your speech ("Sara", "the launch deck") resolve to the right
/// node. That lets Aria's drafts and actions name who and what you actually
/// mean instead of guessing.
///
/// Privacy-first and strictly opt-in: gated by the `app.personalizationEnabled`
/// UserDefaults key (default false). Everything stays on disk locally; nothing
/// leaves the machine. When the user opts out, the store wipes itself so no
/// model of them lingers — mirroring `PersonalContextEngine`.
///
/// Resolution is lexical (see `Entity.relevance`), so `resolve` is a pure,
/// deterministic ranking over the loaded entities — testable without touching
/// the filesystem.
actor EntityStore {
    static let shared = EntityStore()

    /// UserDefaults key for the opt-in master switch. Read directly from
    /// UserDefaults (not AppSettings) so this subsystem stays self-contained.
    static let enabledKey = "app.personalizationEnabled"

    private let storeURL: URL
    private let defaults: UserDefaults
    private var entities: [Entity]
    private let maxEntities = 1000

    init(storeURL: URL? = nil, defaults: UserDefaults = .standard) {
        let url = storeURL ?? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("identity-entities.json")
        self.storeURL = url
        self.defaults = defaults
        self.entities = Self.load(from: url)
    }

    /// Whether the user has opted into personalization. Default false.
    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    var count: Int { entities.count }

    // MARK: Upsert

    /// Remember (or update) an entity. A no-op when personalization is off — and
    /// a privacy guard: it wipes any stored entities so nothing lingers on disk
    /// after the user opts out. Returns the stored entity, or nil when gated.
    ///
    /// Dedupe is by canonical id (name-derived): re-mentioning the same person
    /// merges into the existing node — union of aliases, newer notes win, and
    /// `lastSeen` advances.
    @discardableResult
    func upsert(_ entity: Entity) -> Entity? {
        guard gateForWrite() else { return nil }
        if let idx = entities.firstIndex(where: { $0.id == entity.id }) {
            var merged = entities[idx]
            merged.name = entity.name.isEmpty ? merged.name : entity.name
            merged.kind = entity.kind
            // Union of aliases, order-stable, case-insensitively de-duplicated.
            var seen = Set(merged.aliases.map { $0.lowercased() })
            for a in entity.aliases where !a.isEmpty && !seen.contains(a.lowercased()) {
                merged.aliases.append(a); seen.insert(a.lowercased())
            }
            if !entity.notes.isEmpty { merged.notes = entity.notes }
            merged.lastSeen = max(merged.lastSeen, entity.lastSeen)
            entities[idx] = merged
            save()
            return merged
        }
        entities.append(entity)
        if entities.count > maxEntities { entities.removeFirst(entities.count - maxEntities) }
        save()
        return entity
    }

    // MARK: Resolve / read

    /// Resolve a casual reference ("Sara", "the launch deck") to the best
    /// matching entity, or nil if none plausibly match or personalization is off.
    func resolve(_ reference: String) -> Entity? {
        guard isEnabled else { return nil }
        return Self.rank(reference, in: entities, limit: 1).first
    }

    /// Top entities matching a reference, best first. Empty when gated.
    func search(_ reference: String, limit: Int = 5) -> [Entity] {
        guard isEnabled else { return [] }
        return Self.rank(reference, in: entities, limit: limit)
    }

    /// All known entities (empty when personalization is off — defense in depth;
    /// the store also wipes on disable).
    func all() -> [Entity] {
        guard isEnabled else { return [] }
        return entities
    }

    // MARK: Ranking (pure — testable)

    /// Lexical ranking over a set of entities, best first. Factored out as a
    /// `static` pure function so tests exercise it against in-memory entities
    /// without constructing the actor. Empty reference or empty set returns [].
    static func rank(_ reference: String, in entities: [Entity], limit: Int = 5) -> [Entity] {
        let terms = Entity.terms(reference)
        guard !terms.isEmpty, !entities.isEmpty else { return [] }
        let scored: [(entity: Entity, score: Double)] = entities
            .map { (entity: $0, score: $0.relevance(to: terms)) }
            .filter { $0.score > 0 }
        // Score first; tie-break toward the more recently seen entity.
        let ranked = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.entity.lastSeen > rhs.entity.lastSeen
        }
        return ranked.prefix(max(0, limit)).map { $0.entity }
    }

    // MARK: Privacy gate

    /// Returns true if writes are allowed. When disabled, wipes any stored
    /// entities (and disk) so no model of the user survives an opt-out.
    private func gateForWrite() -> Bool {
        guard isEnabled else {
            if !entities.isEmpty { entities = []; save() }
            return false
        }
        return true
    }

    // MARK: Persistence

    private func save() {
        let encoder = JSONEncoder()
        // Epoch seconds (mirrors PersonalContextEngine): avoids iso8601
        // fractional-second drift on round-trip.
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(entities) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [Entity] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([Entity].self, from: data)) ?? []
    }
}
