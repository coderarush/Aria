import Foundation

/// A noticed chance to help (spec §38). Carries the four ranking dimensions.
struct Opportunity: Identifiable, Sendable {
    let id: UUID
    var title: String
    var reason: String
    var urgency: Double
    var confidence: Double
    var value: Double
    var interruptCost: Double

    init(id: UUID = UUID(), title: String, reason: String,
         urgency: Double, confidence: Double, value: Double, interruptCost: Double) {
        self.id = id
        self.title = title
        self.reason = reason
        self.urgency = urgency
        self.confidence = confidence
        self.value = value
        self.interruptCost = interruptCost
    }
}

/// The signals presence rules inspect (spec §38 inputs).
struct PresenceContext: Sendable {
    var idleSeconds: TimeInterval
    var unfinishedDraft: Bool
    var minutesUntilNextMeeting: Int?
    var activeObjective: UUID?

    init(idleSeconds: TimeInterval = 0,
         unfinishedDraft: Bool = false,
         minutesUntilNextMeeting: Int? = nil,
         activeObjective: UUID? = nil) {
        self.idleSeconds = idleSeconds
        self.unfinishedDraft = unfinishedDraft
        self.minutesUntilNextMeeting = minutesUntilNextMeeting
        self.activeObjective = activeObjective
    }
}

/// A rule that may raise an opportunity from the current presence context.
protocol OpportunityRule: Sendable {
    func evaluate(_ context: PresenceContext) -> Opportunity?
}

/// Evaluates presence rules to surface opportunities (spec §38). Notices only —
/// never acts.
actor OpportunityDetector {

    private var rules: [any OpportunityRule] = []

    func addRule(_ rule: any OpportunityRule) { rules.append(rule) }

    func detect(_ context: PresenceContext) -> [Opportunity] {
        rules.compactMap { $0.evaluate(context) }
    }
}
