import Foundation

/// Cheap heuristic: does this need the multi-step autonomy engine, or is it a
/// quick chat/one-shot for the v3 path? Conjunctions + action verbs + length
/// signal a task. (A model-based router can replace this later.)
enum IntentRouter {
    private static let actionVerbs = ["open", "create", "make", "write", "draft", "send", "email",
                                      "research", "find", "download", "organize", "clean", "build",
                                      "summarize", "schedule", "rename", "move", "delete", "set up"]
    static func isTask(_ command: String) -> Bool {
        let c = command.lowercased()
        let hasConjunction = c.contains(" and ") || c.contains(", then ") || c.contains(" then ")
        let verbCount = actionVerbs.filter { c.contains($0) }.count
        let long = c.split(separator: " ").count >= 8
        return (verbCount >= 1 && (hasConjunction || long)) || verbCount >= 2
    }
}
