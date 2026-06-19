import Foundation

/// Learns from outcomes and proposes improvements (spec §43).
///
/// Tracks suggestion acceptance and per-tool performance, then derives plain
/// recommendations. It never modifies code — it surfaces what should change,
/// for humans or higher layers to act on.
actor LearningEngine {

    private var acceptances = 0
    private var suggestionsSeen = 0
    private var toolStats: [String: (success: Int, failure: Int)] = [:]

    func recordSuggestion(accepted: Bool) {
        suggestionsSeen += 1
        if accepted { acceptances += 1 }
    }

    func recordToolResult(tool: String, success: Bool) {
        var stats = toolStats[tool] ?? (0, 0)
        if success { stats.success += 1 } else { stats.failure += 1 }
        toolStats[tool] = stats
    }

    func acceptanceRate() -> Double {
        guard suggestionsSeen > 0 else { return 0 }
        return Double(acceptances) / Double(suggestionsSeen)
    }

    func toolSuccessRate(_ tool: String) -> Double {
        guard let stats = toolStats[tool] else { return 0 }
        let total = stats.success + stats.failure
        guard total > 0 else { return 0 }
        return Double(stats.success) / Double(total)
    }

    /// Plain-language improvement recommendations (never code changes).
    func improvements() -> [String] {
        var out: [String] = []
        if suggestionsSeen >= 5 && acceptanceRate() < 0.3 {
            out.append("reduce suggestion frequency (low acceptance)")
        }
        for (tool, stats) in toolStats {
            let total = stats.success + stats.failure
            if total >= 4 && toolSuccessRate(tool) < 0.5 {
                out.append("review tool:\(tool) (low success rate)")
            }
        }
        return out
    }
}
