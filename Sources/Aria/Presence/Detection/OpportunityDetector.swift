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
    /// Live Loop: the executable action this opportunity carries. Nil for
    /// notice-only opportunities (the pre-Live-Loop behavior).
    var playbook: PlaybookRef?

    init(id: UUID = UUID(), title: String, reason: String,
         urgency: Double, confidence: Double, value: Double, interruptCost: Double,
         playbook: PlaybookRef? = nil) {
        self.id = id
        self.title = title
        self.reason = reason
        self.urgency = urgency
        self.confidence = confidence
        self.value = value
        self.interruptCost = interruptCost
        self.playbook = playbook
    }
}

/// Two apps the user keeps flipping between — the Live Loop's conservative
/// "manual workflow friction" signal.
struct AppPingPong: Sendable, Equatable {
    let appA: String
    let appB: String
    let count: Int

    init(appA: String, appB: String, count: Int) {
        self.appA = appA
        self.appB = appB
        self.count = count
    }
}

/// The signals presence rules inspect (spec §38 inputs).
struct PresenceContext: Sendable {
    var idleSeconds: TimeInterval
    var unfinishedDraft: Bool
    var minutesUntilNextMeeting: Int?
    var activeObjective: UUID?
    // Live Loop signal fields (all additive; defaults keep pre-Live behavior).
    /// Local hour of day, 0–23. Set by `ClockSignal`.
    var hour: Int
    /// Whether today's daily brief already ran (from `LiveLoopStore`).
    var dailyBriefAlreadyRanToday: Bool
    /// Title of the next upcoming calendar event, when one is near.
    var nextEventTitle: String?
    /// New unread messages since the last look (0 = nothing new).
    var newUnreadMail: Int
    /// Rapid switching between two apps — manual-workflow friction.
    var appPingPong: AppPingPong?

    init(idleSeconds: TimeInterval = 0,
         unfinishedDraft: Bool = false,
         minutesUntilNextMeeting: Int? = nil,
         activeObjective: UUID? = nil,
         hour: Int = 12,
         dailyBriefAlreadyRanToday: Bool = true,
         nextEventTitle: String? = nil,
         newUnreadMail: Int = 0,
         appPingPong: AppPingPong? = nil) {
        self.idleSeconds = idleSeconds
        self.unfinishedDraft = unfinishedDraft
        self.minutesUntilNextMeeting = minutesUntilNextMeeting
        self.activeObjective = activeObjective
        self.hour = hour
        self.dailyBriefAlreadyRanToday = dailyBriefAlreadyRanToday
        self.nextEventTitle = nextEventTitle
        self.newUnreadMail = newUnreadMail
        self.appPingPong = appPingPong
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
