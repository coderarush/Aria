import Foundation

/// Decides what is worth remembering (spec §30).
///
/// `importance = novelty × utility × objectiveRelevance`. Only records scoring
/// at or above the threshold are kept, so memory stays "compressed capability"
/// rather than a transcript.
struct ImportanceScorer: Sendable {

    /// The 0…1 signals that feed the importance formula.
    struct Signals: Sendable {
        var novelty: Double
        var utility: Double
        var objectiveRelevance: Double
    }

    var threshold: Double

    init(threshold: Double = 0.1) {
        self.threshold = threshold
    }

    func score(_ signals: Signals) -> Double {
        signals.novelty * signals.utility * signals.objectiveRelevance
    }

    func shouldStore(_ signals: Signals) -> Bool {
        score(signals) >= threshold
    }
}
