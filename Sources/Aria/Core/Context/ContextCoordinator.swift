import Foundation

/// The world model: merges Aria's existing ambient signals into one canonical
/// `CurrentWorldState`. A READ-ONLY aggregator — it queries the existing engines'
/// public APIs and never mutates them (no refresh/save), so wiring it in changes
/// nothing about how those engines behave. If it's never read, nothing breaks.
///
/// Sources reused as-is: AppFocusMonitor (active app + duration), ClipboardContext
/// (clipboard), WorkJournal (recent completed work). `injectTestState` makes the
/// snapshot deterministic for tests without touching NSWorkspace or the disk.
actor ContextCoordinator {
    static let shared = ContextCoordinator()

    private var injected: CurrentWorldState?

    init() {}

    /// Override the snapshot for tests. Pass nil to resume live aggregation.
    func injectTestState(_ state: CurrentWorldState?) { injected = state }

    /// A fresh snapshot of the current world. Query-only over existing engines.
    func worldState(now: Date = Date()) async -> CurrentWorldState {
        if let injected { return injected }
        let focus = await AppFocusMonitor.shared.snapshot()
        let clip = await ClipboardContext.shared.snapshot()
        let actions = await WorkJournal.shared.recent(5).map { entry -> String in
            "\(entry.ok ? "✓" : "✗") \(entry.title)"
        }
        return CurrentWorldState.build(
            activeApp: focus?.appName ?? "",
            focusSince: focus?.since,
            clipboardSummary: clip,
            openFiles: [],                 // reserved — recent-files source wires in later
            recentActions: actions,
            pendingSuggestion: nil,        // reserved — proactive candidate wires in later
            now: now)
    }

    /// A short text line for the system prompt: "Active: Xcode (2m) · clipboard …".
    func summaryLine(now: Date = Date()) async -> String? {
        let w = await worldState(now: now)
        guard !w.activeApp.isEmpty || w.clipboardSummary != nil else { return nil }
        var parts: [String] = []
        if !w.activeApp.isEmpty {
            parts.append("Active: \(w.activeApp) (\(Int(w.focusDuration / 60))m)")
        }
        if let clip = w.clipboardSummary, !clip.isEmpty {
            parts.append("clipboard: \(clip.prefix(60))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Stream world snapshots on a fixed cadence. Cheap (one snapshot per tick);
    /// callers can take(while:) or break to stop. Reserved for live observers.
    func observeWorld(every seconds: TimeInterval = 2.0) -> AsyncStream<CurrentWorldState> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    continuation.yield(await self.worldState())
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
