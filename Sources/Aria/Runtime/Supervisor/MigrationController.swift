import Foundation

/// A migration promotion/rollback decision (spec §109).
struct MigrationDecision: Sendable {
    enum Action: String, Sendable { case promote, hold, rollback }
    let action: Action
    let from: MigrationStage
    let to: MigrationStage
    let reason: String
}

/// Drives the staged production flip (spec §109): promote on ≥95% parity,
/// rollback on regression, hold otherwise. Rollback is always available and the
/// user never sees the migration. The real flip still requires on-device parity
/// data feeding `decide`.
actor MigrationController {

    private(set) var stage: MigrationStage

    init(stage: MigrationStage = .legacy) {
        self.stage = stage
    }

    private static let order: [MigrationStage] = [.legacy, .shadow, .dual, .preferred, .runtimeOnly, .cleanup]

    static func next(after stage: MigrationStage) -> MigrationStage {
        guard let i = order.firstIndex(of: stage), i + 1 < order.count else { return .cleanup }
        return order[i + 1]
    }

    static func previous(before stage: MigrationStage) -> MigrationStage {
        guard let i = order.firstIndex(of: stage), i > 0 else { return .legacy }
        return order[i - 1]
    }

    func decide(parity: ParityReport) -> MigrationDecision {
        if parity.meetsThreshold && stage != .cleanup {
            return MigrationDecision(action: .promote, from: stage, to: Self.next(after: stage),
                                     reason: "parity \(parity.parity) ≥ threshold")
        }
        if parity.total > 0 && parity.parity < 0.5 && stage != .legacy {
            return MigrationDecision(action: .rollback, from: stage, to: Self.previous(before: stage),
                                     reason: "parity regression \(parity.parity)")
        }
        return MigrationDecision(action: .hold, from: stage, to: stage,
                                 reason: "insufficient parity \(parity.parity)")
    }

    func apply(_ decision: MigrationDecision) {
        stage = decision.to
    }
}
