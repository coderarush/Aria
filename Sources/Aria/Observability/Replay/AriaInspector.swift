import Foundation

/// Sees inside the runtime (spec §56). Ingests events and exposes filtered
/// views — objectives, actions, memory, presence, tools, failures.
actor AriaInspector {

    enum Category { case objectives, actions, memory, events, presence, tools, failures }

    private var log: [AriaEvent] = []

    func ingest(_ events: [AriaEvent]) { log.append(contentsOf: events) }

    func events(in category: Category) -> [AriaEvent] {
        switch category {
        case .events:
            return log
        case .objectives:
            return log.filter { [.objectiveCreated, .objectiveCompleted, .objectiveFailed].contains($0.kind) }
        case .actions:
            return log.filter { [.taskStarted, .taskCompleted, .toolExecuted, .verificationPassed].contains($0.kind) }
        case .memory:
            return log.filter { $0.kind == .memoryStored }
        case .presence:
            return log.filter { [.presenceOpportunity, .suggestionOffered, .suggestionResolved].contains($0.kind) }
        case .tools:
            return log.filter { $0.kind == .toolExecuted }
        case .failures:
            return failures()
        }
    }

    /// Events that recorded a failure (result=failed or an error payload).
    func failures() -> [AriaEvent] {
        log.filter { $0.payload["result"] == "failed" || $0.payload["error"] != nil }
    }

    func count(of kind: AriaEvent.Kind) -> Int { log.filter { $0.kind == kind }.count }
}
