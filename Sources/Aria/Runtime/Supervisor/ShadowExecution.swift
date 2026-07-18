import Foundation

/// Aggregate parity between the legacy and runtime paths (spec §52).
struct ParityReport: Sendable {
    let total: Int
    let matches: Int
    let errors: Int
    let avgOldDuration: TimeInterval
    let avgNewDuration: TimeInterval
    let threshold: Double

    var parity: Double { total == 0 ? 0 : Double(matches) / Double(total) }
    var meetsThreshold: Bool { total > 0 && parity >= threshold }
}

/// Runs the runtime path silently alongside legacy and measures parity
/// (spec §52). Never affects the user — it only records diffs so the migration
/// can be promoted once the runtime matches legacy ≥ threshold (default 95%).
actor ShadowExecution {

    private let legacy: any LegacyExecutor
    private let runtime: any RuntimeExecutor
    private let threshold: Double

    private var diffs: [ExecutionDiff] = []
    private var errors = 0

    init(legacy: any LegacyExecutor, runtime: any RuntimeExecutor, threshold: Double = 0.95) {
        self.legacy = legacy
        self.runtime = runtime
        self.threshold = threshold
    }

    /// Execute both paths, record the comparison, and return the diff. The
    /// result is never served to the user.
    @discardableResult
    func run(_ request: BridgeRequest) async -> ExecutionDiff {
        let old = await legacy.execute(request)
        let new = await runtime.execute(request)
        if !new.success { errors += 1 }
        let equal = new.success && old.output == new.output
        let diff = ExecutionDiff(
            oldResult: old.output,
            newResult: new.output,
            oldDuration: old.duration,
            newDuration: new.duration,
            equal: equal,
            confidence: equal ? 1.0 : 0.0)
        diffs.append(diff)
        return diff
    }

    func report() -> ParityReport {
        let total = diffs.count
        let matches = diffs.filter(\.equal).count
        let avgOld = total == 0 ? 0 : diffs.map(\.oldDuration).reduce(0, +) / Double(total)
        let avgNew = total == 0 ? 0 : diffs.map(\.newDuration).reduce(0, +) / Double(total)
        return ParityReport(total: total, matches: matches, errors: errors,
                            avgOldDuration: avgOld, avgNewDuration: avgNew,
                            threshold: threshold)
    }

    /// Safe to promote past shadow once parity clears the threshold.
    func promotable() -> Bool { report().meetsThreshold }
}
