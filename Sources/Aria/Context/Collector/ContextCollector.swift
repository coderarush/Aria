import Foundation

/// A contributor of partial context to a snapshot (app focus, clipboard,
/// open files, current activity, …).
protocol ContextContributor: Sendable {
    func contribute(to snapshot: inout Domain.ContextSnapshot) async
}

/// Assembles a unified ``Domain/ContextSnapshot`` from registered sources
/// (spec Context: Collector → Assembler → Snapshot).
///
/// Each source layers its slice onto a fresh snapshot; the collector emits
/// `contextChanged` whenever a new snapshot is produced so perception can fan
/// out to the rest of the runtime.
actor ContextCollector {

    private var sources: [any ContextContributor] = []
    private let eventBus: EventBus

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    func addSource(_ source: any ContextContributor) {
        sources.append(source)
    }

    /// Build a snapshot of current reality from all sources, in registration
    /// order, and announce it.
    func snapshot() async -> Domain.ContextSnapshot {
        var snapshot = Domain.ContextSnapshot()
        for source in sources {
            await source.contribute(to: &snapshot)
        }
        await eventBus.emit(AriaEvent(
            kind: .contextChanged,
            source: "ContextCollector",
            payload: ["apps": snapshot.apps.joined(separator: ",")]))
        return snapshot
    }
}
