import Foundation

/// Ranks opportunities so presence surfaces the most worthwhile one (spec §38).
///
/// `score = (urgency + confidence + value) / 3 − interruptCost`. Interrupt cost
/// is subtracted directly so a high-cost interruption must clear a higher bar.
struct OpportunityRanker: Sendable {

    func score(_ opportunity: Opportunity) -> Double {
        (opportunity.urgency + opportunity.confidence + opportunity.value) / 3.0
            - opportunity.interruptCost
    }

    func rank(_ opportunities: [Opportunity]) -> [Opportunity] {
        opportunities.sorted { score($0) > score($1) }
    }
}
