import Foundation

/// Parses the planner model's JSON step array into TaskSteps. Each object has a
/// "summary", exactly one of "agent"/"tool", and an optional "input" dict.
enum PlanParser {
    static func steps(fromJSON raw: String) -> [TaskStep] {
        let cleaned = GeminiClient.stripCodeFences(raw)
        guard let start = cleaned.firstIndex(of: "["),
              let end = cleaned.lastIndex(of: "]"),
              let data = String(cleaned[start...end]).data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { obj in
            guard let summary = obj["summary"] as? String else { return nil }
            let input = (obj["input"] as? [String: Any])?.reduce(into: [String: String]()) {
                $0[$1.key] = String(describing: $1.value)
            } ?? [:]
            if let agent = obj["agent"] as? String { return TaskStep(summary: summary, executor: .agent(agent), input: input) }
            if let tool = obj["tool"] as? String { return TaskStep(summary: summary, executor: .tool(tool), input: input) }
            return nil
        }
    }
}
