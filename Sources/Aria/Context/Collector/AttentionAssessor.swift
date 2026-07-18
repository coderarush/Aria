import Foundation

/// The user's attentional state (spec §40).
struct AttentionAssessment: Sendable {
    enum Mode: String, Sendable { case deepFocus, casual, meeting, idle, transition }

    var mode: Mode
    var focus: Double
    var interruptibility: Double
    var energy: Double
    var flow: Double
}

/// Estimates attention and gates interruptions (spec §40). Presence must
/// respect this: a deep-focus user is only interrupted by something urgent.
struct AttentionAssessor: Sendable {

    func assess(_ context: PresenceContext) -> AttentionAssessment {
        if let minutes = context.minutesUntilNextMeeting, minutes <= 0 {
            return AttentionAssessment(mode: .meeting, focus: 0.7,
                                       interruptibility: 0.1, energy: 0.6, flow: 0.5)
        }
        if context.idleSeconds >= 120 {
            return AttentionAssessment(mode: .idle, focus: 0.1,
                                       interruptibility: 0.9, energy: 0.5, flow: 0.0)
        }
        if context.unfinishedDraft {
            return AttentionAssessment(mode: .deepFocus, focus: 0.9,
                                       interruptibility: 0.2, energy: 0.7, flow: 0.8)
        }
        return AttentionAssessment(mode: .casual, focus: 0.5,
                                   interruptibility: 0.6, energy: 0.6, flow: 0.4)
    }

    /// Allow an interruption when the user is interruptible, or when the
    /// opportunity is urgent enough to override focus.
    func allowsInterruption(_ state: AttentionAssessment, opportunity: Opportunity) -> Bool {
        state.interruptibility >= 0.5 || opportunity.urgency >= 0.8
    }
}
