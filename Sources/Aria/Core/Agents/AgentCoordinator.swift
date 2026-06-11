import Foundation

extension Notification.Name {
    /// Posted by the Agents settings tab after add/remove/toggle so the
    /// coordinator rebuilds its folder watchers.
    static let ariaAgentsChanged = Notification.Name("AriaAgentsChanged")
}

/// Drives background agents: a periodic sweep runs whatever is due, folder
/// watchers fire `.folderChanged` agents, and every completion notifies the
/// user and lands in the run history. Runs are silent (no voice, no orb
/// takeover) and deferred while Aria is speaking or mid-task — background
/// work must never fight the foreground.
@MainActor
final class AgentCoordinator {

    private let store: AgentStore
    private let isBusy: () -> Bool
    /// Executes one autonomy goal, silently. Returns (ok, one-line summary).
    private let runner: (String) async -> (Bool, String)
    private let notify: (String, String) -> Void

    private var timer: Timer?
    private var watchers: [UUID: FolderWatcher] = [:]
    private var running = false

    init(store: AgentStore = .shared,
         isBusy: @escaping () -> Bool,
         runner: @escaping (String) async -> (Bool, String),
         notify: @escaping (String, String) -> Void) {
        self.store = store
        self.isBusy = isBusy
        self.runner = runner
        self.notify = notify
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sweep(now: Date()) }
        }
        Task { await refreshWatchers() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        watchers.values.forEach { $0.stop() }
        watchers = [:]
    }

    /// Run everything due. Serial: one background agent at a time.
    func sweep(now: Date) async {
        guard !running, !isBusy() else { return }
        let due = await store.dueAgents(now: now)
        guard !due.isEmpty else { return }
        running = true
        defer { running = false }
        for agent in due {
            // Re-check between agents — the user may have started talking.
            if isBusy() { break }
            await run(agent)
        }
    }

    /// Rebuild folder watchers from the current agent set. Call after CRUD.
    func refreshWatchers() async {
        watchers.values.forEach { $0.stop() }
        watchers = [:]
        for agent in await store.all() where agent.enabled {
            guard case .folderChanged(let path) = agent.trigger else { continue }
            let id = agent.id
            let watcher = FolderWatcher(path: path) { [weak self] in
                Task { @MainActor in await self?.runFolderAgent(id) }
            }
            if watcher.start() {
                watchers[id] = watcher
            } else {
                Log.trace("agents: cannot watch \(path) — folder missing?")
            }
        }
    }

    private func runFolderAgent(_ id: UUID) async {
        guard !running, !isBusy() else { return }   // next change re-fires; skipping is safe
        guard let agent = await store.all().first(where: { $0.id == id }), agent.enabled else { return }
        running = true
        defer { running = false }
        await run(agent)
    }

    private func run(_ agent: BackgroundAgent) async {
        Log.trace("agents: running '\(agent.name)'")
        let (ok, summary) = await runner(agent.goal)
        await store.markRun(agent.id, at: Date(), ok: ok, summary: summary)
        await WorkJournal.shared.record(kind: .agent, title: agent.name, outcome: summary, ok: ok)
        // Never silent: success or failure, the user can see what happened.
        notify(ok ? "\(agent.name) — done" : "\(agent.name) — failed",
               String(summary.prefix(140)))
    }
}
