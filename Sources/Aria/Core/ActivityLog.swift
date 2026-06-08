import Foundation

/// One action Aria took, recorded for traceability. The directive requires every
/// action to be "visible and traceable" — `TaskEvent`/narration covers *visible*
/// during a run; this is the *durable, traceable* record that survives restarts.
struct ActivityEntry: Codable, Equatable, Identifiable, Sendable {
    enum Outcome: String, Codable, Sendable { case ok, failed, declined }

    let id: UUID
    let date: Date
    let tool: String
    /// Short, redacted summary of the input (no raw secrets / huge blobs).
    let detail: String
    let outcome: Outcome
    /// Short snippet of the result, for the activity view.
    let summary: String

    init(id: UUID = UUID(), date: Date = Date(), tool: String,
         detail: String, outcome: Outcome, summary: String) {
        self.id = id
        self.date = date
        self.tool = tool
        self.detail = detail
        self.outcome = outcome
        self.summary = summary
    }

    /// Map a tool result to an outcome, keeping decline distinct from failure
    /// (a user-declined gate is not an error).
    static func outcome(for result: ToolResult) -> Outcome {
        if result.success { return .ok }
        return result.wasDeclined ? .declined : .failed
    }

    /// Trim a free-text field to a single short line for the log.
    static func tidy(_ text: String, max: Int = 140) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLine.count <= max ? oneLine : String(oneLine.prefix(max)) + "…"
    }
}

/// Append-only, capped activity log persisted as JSON in Application Support, so
/// past actions stay traceable across launches. An actor — safe to record into
/// from any task (the execution chokepoint runs concurrently).
actor ActivityLog {
    static let shared = ActivityLog()

    private let url: URL
    private let cap: Int
    private var entries: [ActivityEntry] = []
    private var loaded = false

    init(url: URL? = nil, cap: Int = 500) {
        self.url = url ?? ActivityLog.defaultURL()
        self.cap = cap
    }

    /// Record one action's outcome. Cheap: keeps the last `cap` entries and writes
    /// the (small) file atomically.
    func record(tool: String, detail: String, result: ToolResult) {
        load()
        let entry = ActivityEntry(
            tool: tool,
            detail: ActivityEntry.tidy(detail),
            outcome: ActivityEntry.outcome(for: result),
            summary: ActivityEntry.tidy(result.output))
        entries = ActivityLog.trimmed(entries + [entry], cap: cap)
        persist()
    }

    /// The most recent entries, newest first — for an activity view or audit.
    func recent(_ limit: Int = 50) -> [ActivityEntry] {
        load()
        return Array(entries.suffix(limit).reversed())
    }

    func clear() {
        entries = []
        loaded = true
        persist()
    }

    // MARK: - Pure helpers (unit-tested)

    /// Keep only the last `cap` entries.
    static func trimmed(_ entries: [ActivityEntry], cap: Int) -> [ActivityEntry] {
        entries.count <= cap ? entries : Array(entries.suffix(cap))
    }

    static func defaultURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Aria/activity.json")
    }

    // MARK: - Persistence

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ActivityEntry].self, from: data)
        else { return }
        entries = ActivityLog.trimmed(decoded, cap: cap)
    }

    private func persist() {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
