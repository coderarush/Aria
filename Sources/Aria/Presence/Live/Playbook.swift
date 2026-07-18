import Foundation

/// How much freedom a playbook has when its recognizer fires (Live Loop design
/// 2026-06-24). `auto` is reserved for read-only/prep work (gather, brief,
/// open); anything outward or mutating ships as `confirm`. `Safety` still vets
/// every tool call regardless of tier — this gate only decides whether Aria
/// may *start* without asking.
enum AutonomyTier: String, Codable, Sendable, CaseIterable {
    case auto
    case confirm
    case off

    var label: String {
        switch self {
        case .auto: return "Act automatically"
        case .confirm: return "Ask first"
        case .off: return "Off"
        }
    }
}

/// A recognized opportunity's pointer to the action to take: which playbook,
/// plus the context values the recognizer bound (event title, app names…).
struct PlaybookRef: Sendable, Equatable {
    let id: String
    var inputs: [String: String]

    init(id: String, inputs: [String: String] = [:]) {
        self.id = id
        self.inputs = inputs
    }
}

/// A named action template the Live Loop can run. The command is a single
/// natural-language instruction dispatched through the EXISTING orchestrator /
/// autonomy engine / tool registry — there is no second execution engine.
/// `{{key}}` placeholders are bound from the `PlaybookRef` inputs.
struct Playbook: Sendable {
    let id: String
    let title: String
    /// The tier this playbook ships with; users can tighten/loosen per
    /// recognizer in Settings (see `LiveLoopSettings`).
    let defaultTier: AutonomyTier
    /// Natural-language command template for the orchestrator.
    let commandTemplate: String
    /// One-line spoken offer template for confirm-tier surfacing.
    let offerTemplate: String
}

/// A playbook with its templates bound to concrete inputs — ready to dispatch.
struct ResolvedPlaybook: Sendable {
    let playbook: Playbook
    let command: String
    let offer: String
}

/// The built-in playbook catalog. Resolution fails (returns nil) if any
/// placeholder stays unbound, so a half-filled template can never reach the
/// orchestrator.
enum PlaybookLibrary {

    static let meetingPrep = "meeting_prep"
    static let inboxTriage = "inbox_triage"
    static let screenCoPilot = "screen_copilot"
    static let dailyBrief = "daily_brief"

    static let all: [String: Playbook] = [
        meetingPrep: Playbook(
            id: meetingPrep,
            title: "Meeting prep",
            defaultTier: .auto,
            commandTemplate: "Prepare me for my meeting “{{event_title}}” starting in {{minutes}} minutes: search my recent mail for the latest thread about it, recall anything I've noted about it or its attendees, then give me a short spoken brief.",
            offerTemplate: "“{{event_title}}” starts in {{minutes}} minutes — want the prep brief?"),
        inboxTriage: Playbook(
            id: inboxTriage,
            title: "Inbox triage",
            defaultTier: .confirm,
            commandTemplate: "Check my recent unread email, summarize what's new in one breath, and draft (do NOT send) a reply to the most important message in my usual writing style.",
            offerTemplate: "New mail just landed — want me to triage it and draft the important reply?"),
        screenCoPilot: Playbook(
            id: screenCoPilot,
            title: "Screen co-pilot",
            defaultTier: .confirm,
            commandTemplate: "I keep switching between {{app_a}} and {{app_b}} doing something repetitive. Look at my screen, figure out the workflow, and either walk me through a faster way or do the next round for me.",
            offerTemplate: "You've bounced between {{app_a}} and {{app_b}} a lot — want a hand with that?"),
        dailyBrief: Playbook(
            id: dailyBrief,
            title: "Daily brief",
            defaultTier: .auto,
            commandTemplate: "Give me my daily briefing: today's calendar, anything important in unread mail, my reminders, and what I was working on yesterday. Keep it tight and speak it.",
            offerTemplate: "Morning — want your daily brief?"),
    ]

    /// Bind a ref's inputs into its playbook templates. Nil when the playbook
    /// is unknown or any `{{placeholder}}` remains unbound.
    static func resolve(_ ref: PlaybookRef) -> ResolvedPlaybook? {
        guard let playbook = all[ref.id] else { return nil }
        guard let command = bind(playbook.commandTemplate, inputs: ref.inputs),
              let offer = bind(playbook.offerTemplate, inputs: ref.inputs) else { return nil }
        return ResolvedPlaybook(playbook: playbook, command: command, offer: offer)
    }

    private static func bind(_ template: String, inputs: [String: String]) -> String? {
        var out = template
        for (key, value) in inputs {
            out = out.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return out.contains("{{") ? nil : out
    }
}
