import Foundation

/// One step of a guided walkthrough: the on-screen thing to act on, and what to
/// do with it.
struct WalkthroughStep: Equatable {
    let element: String
    let instruction: String
}

/// Maps an explicit "teach me how" command to the task to walk through. Kept
/// deliberately explicit (a tutorial mode you ask for) so plain how-to questions
/// the user wants *answered*, not *demonstrated*, still route to the agent. Pure.
enum WalkthroughIntent {
    private static let leads = [
        "walk me through", "show me how to", "show me how i", "guide me through",
        "teach me how to", "walk through how to", "can you show me how to"
    ]

    /// Returns the task to demonstrate (the words after the lead phrase), or nil.
    static func task(for command: String) -> String? {
        let c = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for lead in leads where c.contains(lead) {
            guard let r = c.range(of: lead) else { continue }
            var rest = String(c[r.upperBound...])
            rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " :,-")).trimmingCharacters(in: .whitespaces)
            // Strip a trailing filler ("... on my screen", "... in this app").
            return rest.isEmpty ? nil : rest
        }
        return nil
    }
}

/// Parses a model's JSON reply into ordered walkthrough steps. Tolerant: accepts
/// a fenced or bare array of objects, with `element`/`target` and
/// `instruction`/`do`/`action` keys. Pure + testable; never throws.
enum WalkthroughPlan {
    static func parse(_ raw: String, maxSteps: Int = 6) -> [WalkthroughStep] {
        let cleaned = stripFences(raw)
        guard let start = cleaned.firstIndex(of: "["),
              let end = cleaned.lastIndex(of: "]"),
              let data = String(cleaned[start...end]).data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var out: [WalkthroughStep] = []
        for obj in arr {
            let element = str(obj, "element") ?? str(obj, "target") ?? str(obj, "where") ?? ""
            let instruction = str(obj, "instruction") ?? str(obj, "do") ?? str(obj, "action") ?? str(obj, "step") ?? ""
            guard !instruction.isEmpty else { continue }
            out.append(WalkthroughStep(element: element, instruction: instruction))
            if out.count >= maxSteps { break }
        }
        return out
    }

    private static func str(_ obj: [String: Any], _ key: String) -> String? {
        guard let s = (obj[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private static func stripFences(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let nl = s.firstIndex(of: "\n") { s = String(s[s.index(after: nl)...]) }
            if let fence = s.range(of: "```", options: .backwards) { s = String(s[..<fence.lowerBound]) }
        }
        return s
    }
}
