import Foundation

/// A point-in-time snapshot of an in-flight work session — the bits WorkJournal
/// (which records *completed* work) doesn't carry: the live goal, where things
/// stand, what's blocking, and the next step. Powers "continue yesterday" /
/// "what was I doing?" by giving the first summon of the day a real answer.
struct SessionSnapshot: Codable, Equatable, Sendable {
    let project: String?
    let goal: String
    let progress: String
    let blockers: [String]
    let nextStep: String?
    let date: Date
    /// When this snapshot stops being relevant (local memory expiration).
    let expiresAt: Date

    init(project: String?,
         goal: String,
         progress: String = "",
         blockers: [String] = [],
         nextStep: String? = nil,
         date: Date = Date(),
         ttlDays: Int = 14) {
        self.project = project
        self.goal = goal
        self.progress = progress
        self.blockers = blockers
        self.nextStep = nextStep
        self.date = date
        self.expiresAt = date.addingTimeInterval(Double(ttlDays) * 86_400)
    }
}

/// Local-first session continuation store. Snapshots persist to disk, expire on
/// their own schedule, and are pruned whenever a new one is recorded. Nothing
/// leaves the machine. Complements WorkJournal/Timeline — it does not replace them.
actor SessionMemoryStore {
    static let shared = SessionMemoryStore()

    private let fileURL: URL
    private let cap: Int
    private var snapshots: [SessionSnapshot]

    init(fileURL: URL? = nil, cap: Int = 200) {
        let url = fileURL ?? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("session-snapshots.json")
        self.fileURL = url
        self.cap = cap
        self.snapshots = Self.load(from: url)
    }

    /// Record a snapshot, pruning any that have expired by `now`.
    func record(_ snapshot: SessionSnapshot, now: Date = Date()) {
        snapshots.removeAll { $0.expiresAt <= now }
        snapshots.append(snapshot)
        if snapshots.count > cap { snapshots.removeFirst(snapshots.count - cap) }
        save()
    }

    /// Newest non-expired snapshot, optionally scoped to a project (case-insensitive).
    func latest(project: String? = nil, now: Date = Date()) -> SessionSnapshot? {
        active(now: now)
            .filter { project == nil || $0.project?.lowercased() == project?.lowercased() }
            .max(by: { $0.date < $1.date })
    }

    /// All non-expired snapshots, newest first.
    func active(now: Date = Date()) -> [SessionSnapshot] {
        snapshots.filter { $0.expiresAt > now }.sorted { $0.date > $1.date }
    }

    /// Human-readable resume line for "continue yesterday" — goal + next step + blockers.
    func resumeDigest(project: String? = nil, now: Date = Date()) -> String? {
        guard let s = latest(project: project, now: now) else { return nil }
        var line = s.goal
        if let next = s.nextStep, !next.isEmpty { line += " — next: \(next)" }
        if !s.blockers.isEmpty { line += " (blocked on: \(s.blockers.joined(separator: ", ")))" }
        return line
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(snapshots) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [SessionSnapshot] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([SessionSnapshot].self, from: data)) ?? []
    }
}
