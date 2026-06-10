import Foundation

/// What causes a background agent to run.
enum AgentTrigger: Codable, Equatable, Sendable {
    /// Once per day, at or after the given local time.
    case daily(hour: Int, minute: Int)
    /// At most once per `seconds` interval.
    case interval(seconds: TimeInterval)
    /// When the watched folder's contents change (fired by FolderWatcher, not
    /// the timer sweep).
    case folderChanged(path: String)
}

/// A user-visible recurring workflow ("set it once, let Aria handle it"):
/// daily briefing, folder monitoring, any recurring autonomy goal. Runs go
/// through the same AutonomyEngine + Safety gates as voice tasks, silently,
/// and every run is recorded — background agents must never feel hidden.
struct BackgroundAgent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    /// The autonomy goal handed to the engine, verbatim.
    var goal: String
    var trigger: AgentTrigger
    var enabled: Bool
    var lastRun: Date?
    var lastOutcome: String?

    init(id: UUID = UUID(), name: String, goal: String, trigger: AgentTrigger,
         enabled: Bool = true, lastRun: Date? = nil, lastOutcome: String? = nil) {
        self.id = id
        self.name = name
        self.goal = goal
        self.trigger = trigger
        self.enabled = enabled
        self.lastRun = lastRun
        self.lastOutcome = lastOutcome
    }
}

/// One completed run, kept for the workflow-history view.
struct AgentRun: Codable, Equatable, Sendable {
    let agentID: UUID
    let agentName: String
    let date: Date
    let ok: Bool
    let summary: String
}

/// Pure due-time math, separated for testability.
enum AgentSchedule {
    static func isDue(_ trigger: AgentTrigger, now: Date, lastRun: Date?,
                      calendar: Calendar = .current) -> Bool {
        switch trigger {
        case .daily(let hour, let minute):
            guard let slot = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now),
                  now >= slot else { return false }
            guard let last = lastRun else { return true }
            return !calendar.isDate(last, inSameDayAs: now)
        case .interval(let seconds):
            guard let last = lastRun else { return true }
            return now.timeIntervalSince(last) >= seconds
        case .folderChanged:
            return false   // watcher-fired, never timer-due
        }
    }
}

/// Persisted set of background agents + their run history.
actor AgentStore {
    static let shared = AgentStore()

    private struct State: Codable {
        var agents: [BackgroundAgent] = []
        var runs: [AgentRun] = []
    }

    private let fileURL: URL
    private var state: State
    private let runCap = 100

    init(fileURL: URL? = nil) {
        let url = fileURL ?? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("agents.json")
        self.fileURL = url
        self.state = Self.load(from: url)
    }

    func all() -> [BackgroundAgent] { state.agents }

    func upsert(_ agent: BackgroundAgent) {
        if let idx = state.agents.firstIndex(where: { $0.id == agent.id }) {
            state.agents[idx] = agent
        } else {
            state.agents.append(agent)
        }
        save()
    }

    func remove(_ id: UUID) {
        state.agents.removeAll { $0.id == id }
        save()
    }

    /// Enabled agents whose trigger is due right now (timer sweep).
    func dueAgents(now: Date = Date()) -> [BackgroundAgent] {
        state.agents.filter { $0.enabled && AgentSchedule.isDue($0.trigger, now: now, lastRun: $0.lastRun) }
    }

    /// Record a completed run: stamps the agent and appends to history.
    func markRun(_ id: UUID, at date: Date = Date(), ok: Bool, summary: String) {
        guard let idx = state.agents.firstIndex(where: { $0.id == id }) else { return }
        state.agents[idx].lastRun = date
        state.agents[idx].lastOutcome = summary
        state.runs.append(AgentRun(agentID: id, agentName: state.agents[idx].name,
                                   date: date, ok: ok, summary: summary))
        if state.runs.count > runCap { state.runs.removeFirst(state.runs.count - runCap) }
        save()
    }

    /// Newest first.
    func recentRuns(_ limit: Int) -> [AgentRun] {
        Array(state.runs.suffix(limit).reversed())
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(state) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> State {
        guard let data = try? Data(contentsOf: url) else { return State() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode(State.self, from: data)) ?? State()
    }
}
