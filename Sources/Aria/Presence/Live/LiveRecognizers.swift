import Foundation

/// The four Live Loop v1 recognizers (design 2026-06-24). Each is a pure
/// `OpportunityRule`: fixture context in → `Opportunity` with a bound
/// `PlaybookRef` out. No I/O, no LLM — detection stays local and cheap;
/// reasoning happens only inside the playbook once a recognizer fires.

/// A meeting starts within the prep window → assemble a spoken brief (auto:
/// read-only prep).
struct MeetingPrepRule: OpportunityRule {
    /// Fire when the next event starts within this many minutes.
    var windowMinutes: Int = 15

    func evaluate(_ context: PresenceContext) -> Opportunity? {
        guard let minutes = context.minutesUntilNextMeeting,
              minutes >= 0, minutes <= windowMinutes,
              let title = context.nextEventTitle, !title.isEmpty else { return nil }
        // Urgency rises as the meeting gets closer.
        let urgency = 0.7 + 0.3 * (1 - Double(minutes) / Double(max(1, windowMinutes)))
        return Opportunity(
            title: "Prep for “\(title)”",
            reason: "Meeting starts in \(minutes) min",
            urgency: min(1, urgency), confidence: 0.9, value: 0.85, interruptCost: 0.15,
            playbook: PlaybookRef(id: PlaybookLibrary.meetingPrep,
                                  inputs: ["event_title": title, "minutes": String(minutes)]))
    }
}

/// New unread mail landed → offer to triage + draft the important reply
/// (confirm: drafting touches an outward surface even though nothing sends).
struct InboxTriageRule: OpportunityRule {
    func evaluate(_ context: PresenceContext) -> Opportunity? {
        guard context.newUnreadMail > 0 else { return nil }
        let volume = min(1, Double(context.newUnreadMail) / 5.0)
        return Opportunity(
            title: "Triage new mail",
            reason: "\(context.newUnreadMail) new unread message\(context.newUnreadMail == 1 ? "" : "s")",
            urgency: 0.4 + 0.2 * volume, confidence: 0.75, value: 0.6, interruptCost: 0.3,
            playbook: PlaybookRef(id: PlaybookLibrary.inboxTriage))
    }
}

/// The user keeps flipping between the same two apps — a manual workflow Aria
/// can probably shortcut (confirm: she'll look at the screen first).
struct ScreenCoPilotRule: OpportunityRule {
    /// Minimum A↔B switches inside the signal's window before this fires.
    var minSwitches: Int = 6

    func evaluate(_ context: PresenceContext) -> Opportunity? {
        guard let pingPong = context.appPingPong, pingPong.count >= minSwitches else { return nil }
        return Opportunity(
            title: "Help with \(pingPong.appA) ↔ \(pingPong.appB)",
            reason: "\(pingPong.count) switches in the last couple of minutes",
            urgency: 0.5, confidence: 0.65, value: 0.7, interruptCost: 0.35,
            playbook: PlaybookRef(id: PlaybookLibrary.screenCoPilot,
                                  inputs: ["app_a": pingPong.appA, "app_b": pingPong.appB]))
    }
}

/// First activity of the morning → the daily brief (auto: read-only synthesis,
/// the JARVIS "good morning").
struct DailyBriefRule: OpportunityRule {
    /// Local hours considered "morning".
    var morningHours: ClosedRange<Int> = 5...11

    func evaluate(_ context: PresenceContext) -> Opportunity? {
        guard morningHours.contains(context.hour),
              !context.dailyBriefAlreadyRanToday else { return nil }
        return Opportunity(
            title: "Daily brief",
            reason: "First activity of the morning",
            urgency: 0.6, confidence: 0.85, value: 0.8, interruptCost: 0.2,
            playbook: PlaybookRef(id: PlaybookLibrary.dailyBrief))
    }
}
