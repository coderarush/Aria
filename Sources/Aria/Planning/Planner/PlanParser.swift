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
            if let agent = obj["agent"] as? String {
                var step = TaskStep(summary: summary, executor: .agent(agent), input: input)
                step.postCondition = condition(from: obj["verify"], input: input, tool: nil)
                return step
            }
            if let tool = obj["tool"] as? String {
                var step = TaskStep(summary: summary, executor: .tool(tool), input: input)
                step.postCondition = condition(from: obj["verify"], input: input, tool: tool)
                return step
            }
            return nil
        }
    }

    /// The planner may request only local, deterministic checks. Unknown forms
    /// intentionally become `.none`: an invented verifier must never cause a
    /// false claim or silently change a plan's meaning.
    private static func condition(from raw: Any?, input: [String: String], tool: String?) -> PostCondition {
        guard let verify = raw as? [String: Any],
              let kind = verify["kind"] as? String
        else { return .none }
        switch kind.lowercased() {
        case "app_running":
            guard let name = verify["name"] as? String, !name.isEmpty else { return .none }
            return .appRunning(name)
        case "app_not_running":
            guard let name = verify["name"] as? String, !name.isEmpty else { return .none }
            return .appNotRunning(name)
        case "file_exists":
            guard let path = verify["path"] as? String,
                  !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  tool == "file_write",
                  input["path"] == path else { return .none }
            return .fileExists(path)
        case "result_contains":
            guard let text = verify["text"] as? String, !text.isEmpty else { return .none }
            return .resultContains(text)
        case "succeeded":
            return .succeeded
        default:
            return .none
        }
    }
}
