import Foundation

/// A surfaced, dismissible suggestion (spec §39). Short, actionable text plus
/// the user's response.
struct PresenceSuggestion: Identifiable, Sendable {
    enum State: String, Sendable { case pending, accepted, dismissed, ignored }

    let id: UUID
    var text: String
    var opportunityID: UUID?
    var state: State

    init(id: UUID = UUID(), text: String, opportunityID: UUID? = nil, state: State = .pending) {
        self.id = id
        self.text = text
        self.opportunityID = opportunityID
        self.state = state
    }
}

/// Offers suggestions and records how the user responds (spec §39), so presence
/// can learn what's welcome. Emits `suggestionOffered` / `suggestionResolved`.
actor SuggestionEngine {

    private var suggestions: [UUID: PresenceSuggestion] = [:]
    private let eventBus: EventBus

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    @discardableResult
    func suggest(text: String, opportunityID: UUID? = nil) async -> PresenceSuggestion {
        let suggestion = PresenceSuggestion(text: text, opportunityID: opportunityID)
        suggestions[suggestion.id] = suggestion
        await eventBus.emit(AriaEvent(
            kind: .suggestionOffered,
            source: "SuggestionEngine",
            payload: ["id": suggestion.id.uuidString, "text": text]))
        return suggestion
    }

    func get(_ id: UUID) -> PresenceSuggestion? { suggestions[id] }

    func accept(_ id: UUID) async { await resolve(id, to: .accepted) }
    func dismiss(_ id: UUID) async { await resolve(id, to: .dismissed) }
    func ignore(_ id: UUID) async { await resolve(id, to: .ignored) }

    func stats() -> (accepted: Int, dismissed: Int, ignored: Int) {
        var accepted = 0, dismissed = 0, ignored = 0
        for suggestion in suggestions.values {
            switch suggestion.state {
            case .accepted: accepted += 1
            case .dismissed: dismissed += 1
            case .ignored: ignored += 1
            case .pending: break
            }
        }
        return (accepted, dismissed, ignored)
    }

    private func resolve(_ id: UUID, to state: PresenceSuggestion.State) async {
        guard suggestions[id] != nil else { return }
        suggestions[id]?.state = state
        await eventBus.emit(AriaEvent(
            kind: .suggestionResolved,
            source: "SuggestionEngine",
            payload: ["id": id.uuidString, "state": state.rawValue]))
    }
}
