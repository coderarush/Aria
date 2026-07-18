import Foundation

/// The concise explanation behind an action — why, how sure, what else was considered.
struct ActionReasoning: Equatable, Sendable {
    let why: String
    let confidence: Double
    let alternatives: [String]
}

/// ReasoningPanel (Phase 10): explainability for what Aria proposes — why /
/// confidence / alternatives. It is a READ/COMPUTE layer over the existing
/// signals: it reuses IntentEngine's ranked `PredictedIntent` candidates (which
/// already carry confidence + reasoning) rather than building a parallel reasoning
/// ledger, and it does not touch approval/undo (the Trust layer already owns
/// Preview/Approve/Execute/Undo). No chain-of-thought: the reason is reduced to a
/// single concise line.
enum ReasoningPanel {

    /// Explain the chosen action from ranked candidates. With a world state, reuses
    /// IntentEngine's context-aware ranking; otherwise sorts by confidence.
    static func explain(_ candidates: [PredictedIntent], world: CurrentWorldState? = nil,
                        floor: Double = 0) -> ActionReasoning? {
        let ranked: [PredictedIntent]
        if let world {
            ranked = IntentEngine.rank(candidates, world: world, floor: floor)
        } else {
            ranked = candidates.filter { $0.confidence >= floor }
                .sorted { $0.confidence > $1.confidence }
        }
        guard let top = ranked.first else { return nil }
        return ActionReasoning(why: concise(top.reasoning),
                               confidence: top.confidence,
                               alternatives: Array(ranked.dropFirst().prefix(3).map(\.action)))
    }

    /// Reduce reasoning to one concise line — never chain-of-thought.
    private static func concise(_ text: String, max: Int = 160) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstSentence = oneLine.split(separator: ".", maxSplits: 1,
                                          omittingEmptySubsequences: true).first.map(String.init) ?? oneLine
        let trimmed = firstSentence.trimmingCharacters(in: .whitespaces)
        return trimmed.count <= max ? trimmed : String(trimmed.prefix(max)) + "…"
    }
}
