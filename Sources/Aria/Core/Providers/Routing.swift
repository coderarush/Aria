import Foundation

/// What kind of work a request is — the unit the local/cloud routing decision is
/// made on (V9 constitution: "90% local / 10% cloud" is a per-task-class target).
enum TaskClass: String, Codable, CaseIterable, Sendable {
    case fileOps                // file management, renaming, organizing
    case productivity           // calendar, email, reminders, notes
    case contextRetrieval       // clipboard, selection, screen, tabs
    case memory                 // remember/recall facts
    case documentUnderstanding  // summarize/translate/extract from docs
    case planning               // workflow planning, step structuring
    case simpleChat             // small talk, quick questions
    case deepResearch           // multi-source web research, comparisons
    case complexReasoning       // code analysis, refactors, large synthesis
    case vision                 // needs to see an image
}

/// Where a request runs.
enum ProviderTier: String, Codable, Sendable {
    case local
    case cloud
}

/// One routing decision, with the reason — feeds the Model Router Dashboard
/// (transparency: "avoid black-box behavior").
struct RoutingDecision: Codable, Equatable, Sendable {
    let taskClass: TaskClass
    let tier: ProviderTier
    let reason: String
}

/// Keyword heuristic command → TaskClass. Deliberately conservative: anything
/// ambiguous lands in `simpleChat`/cloud, never accidentally on a weaker local
/// model. Can be model-driven later without changing consumers.
enum TaskClassifier {
    private static let rules: [(TaskClass, [String])] = [
        (.deepResearch, ["research", "compare", "competitive", "best ", "investigate", "sources"]),
        (.complexReasoning, ["analyze", "refactor", "debug", "codebase", "architecture", "step by step"]),
        (.vision, ["look at", "what's on my screen", "this image", "diagram"]),
        (.memory, ["remember", "recall", "what do you know about me", "forget"]),
        (.documentUnderstanding, ["summarize", "summarise", "translate", "extract", "tldr", "key points"]),
        (.fileOps, ["file", "files", "folder", "rename", "organize", "organise", "downloads"]),
        (.productivity, ["calendar", "email", "mail", "remind", "reminder", "note", "meeting", "schedule"]),
        (.contextRetrieval, ["clipboard", "copied", "copy", "selected", "selection", "this tab", "current window"]),
        (.planning, ["plan ", "workflow", "steps to"]),
    ]

    static func classify(_ command: String) -> TaskClass {
        let c = command.lowercased()
        for (cls, words) in rules where words.contains(where: c.contains) {
            return cls
        }
        return .simpleChat
    }
}

/// The routing table. Local-first is opt-in (master toggle); even then, only
/// classes the constitution marks local-eligible prefer the local model, and a
/// dead local server always falls back to cloud. Cloud behavior is therefore
/// byte-identical until the user opts in — preservation by default.
enum RoutingPolicy {
    /// Local-primary (constitution: "local is default, cloud is optional"):
    /// everything runs on the local model except the 10% an 8B model genuinely
    /// can't match — deep research, heavy reasoning, and vision.
    static let localEligible: Set<TaskClass> = [
        .fileOps, .productivity, .contextRetrieval, .memory,
        .documentUnderstanding, .planning, .simpleChat
    ]

    static func route(taskClass: TaskClass,
                      localFirstEnabled: Bool,
                      localAvailable: Bool) -> RoutingDecision {
        guard localFirstEnabled else {
            return RoutingDecision(taskClass: taskClass, tier: .cloud, reason: "local-first off")
        }
        guard localEligible.contains(taskClass) else {
            return RoutingDecision(taskClass: taskClass, tier: .cloud,
                                   reason: "\(taskClass.rawValue) is a cloud-class task")
        }
        guard localAvailable else {
            return RoutingDecision(taskClass: taskClass, tier: .cloud, reason: "local model unreachable")
        }
        return RoutingDecision(taskClass: taskClass, tier: .local,
                               reason: "\(taskClass.rawValue) is local-eligible")
    }
}
