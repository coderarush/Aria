import Foundation

/// An anticipated, surfaced opportunity to help (spec §presence).
struct PresenceOpportunity: Sendable, Equatable {
    let title: String
    let reason: String
    let priority: Domain.Priority
}

/// A rule that inspects current context and may raise an opportunity.
protocol PresenceRule: Sendable {
    func evaluate(_ snapshot: Domain.ContextSnapshot) -> PresenceOpportunity?
}

/// Evaluates presence rules against a context snapshot and emits a
/// `presenceOpportunity` event per match (spec Presence: Detection).
///
/// Detection is decoupled from acting: the detector only surfaces
/// opportunities; whether/how to act is decided downstream by suggestion and
/// permission policy.
actor PresenceDetector {

    private var rules: [any PresenceRule] = []
    private let eventBus: EventBus

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    func addRule(_ rule: any PresenceRule) {
        rules.append(rule)
    }

    func detect(in snapshot: Domain.ContextSnapshot) async -> [PresenceOpportunity] {
        var hits: [PresenceOpportunity] = []
        for rule in rules {
            guard let opportunity = rule.evaluate(snapshot) else { continue }
            hits.append(opportunity)
            await eventBus.emit(AriaEvent(
                kind: .presenceOpportunity,
                source: "PresenceDetector",
                payload: ["title": opportunity.title, "reason": opportunity.reason],
                priority: opportunity.priority == .critical ? .critical : .high))
        }
        return hits
    }
}
