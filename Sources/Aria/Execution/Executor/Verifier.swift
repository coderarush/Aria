import Foundation

/// The result of checking an execution against its verification rules.
struct VerificationOutcome: Sendable {
    let passed: Bool
    let failedRules: [String]
}

/// Checks an ``ExecutionReport`` against a plan's verification rules
/// (spec §16 VerificationRules / §13 verification stage).
///
/// Rule grammar (extensible):
/// - `artifact:<kind>`     — an artifact of that kind was produced
/// - `minCompleted:<n>`    — at least n actions completed
/// - anything else         — passes iff the run as a whole succeeded
struct Verifier: Sendable {

    func verify(report: ExecutionReport, rules: [String]) -> VerificationOutcome {
        let failed = rules.filter { !passes($0, report: report) }
        return VerificationOutcome(passed: failed.isEmpty, failedRules: failed)
    }

    private func passes(_ rule: String, report: ExecutionReport) -> Bool {
        if let kind = value(of: "artifact", in: rule) {
            return report.artifacts.contains { $0.kind.rawValue == kind }
        }
        if let raw = value(of: "minCompleted", in: rule), let n = Int(raw) {
            return report.completed.count >= n
        }
        return report.success
    }

    private func value(of prefix: String, in rule: String) -> String? {
        let token = prefix + ":"
        guard rule.hasPrefix(token) else { return nil }
        return String(rule.dropFirst(token.count))
    }
}
