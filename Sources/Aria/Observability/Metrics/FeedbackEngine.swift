import Foundation

/// Behavioral feedback signals (spec §114).
enum FeedbackKind: String, Sendable { case accept, reject, correct, ignore }

/// What behavior reveals about the product (spec §114).
struct ProductInsights: Sendable {
    let accepts: Int
    let rejects: Int
    let corrects: Int
    let ignores: Int

    var acceptanceRate: Double {
        let total = accepts + rejects + corrects + ignores
        return total == 0 ? 0 : Double(accepts) / Double(total)
    }
}

/// Collects feedback from behavior, not surveys (spec §114): accept/reject/
/// correct/ignore → ``ProductInsights``.
actor FeedbackEngine {

    private var counts: [FeedbackKind: Int] = [:]

    func record(_ kind: FeedbackKind) { counts[kind, default: 0] += 1 }

    func insights() -> ProductInsights {
        ProductInsights(accepts: counts[.accept] ?? 0,
                        rejects: counts[.reject] ?? 0,
                        corrects: counts[.correct] ?? 0,
                        ignores: counts[.ignore] ?? 0)
    }
}
