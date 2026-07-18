import Foundation

/// A tool's operational health (spec §53).
enum ToolHealth: String, Sendable { case healthy, degraded, disabled, blocked, unknown }

/// Governs tool selection by tracking success/latency/retries and deriving a
/// health state (spec §53). Blocking overrides everything.
actor ToolGovernor {

    private struct Stats { var success = 0; var failure = 0; var latency: TimeInterval = 0; var retries = 0 }

    private var stats: [String: Stats] = [:]
    private var blocked: Set<String> = []

    func record(tool: String, success: Bool, latency: TimeInterval, retries: Int = 0) {
        var s = stats[tool] ?? Stats()
        if success { s.success += 1 } else { s.failure += 1 }
        s.latency += latency
        s.retries += retries
        stats[tool] = s
    }

    func block(_ tool: String) { blocked.insert(tool) }
    func unblock(_ tool: String) { blocked.remove(tool) }

    func successRate(_ tool: String) -> Double {
        guard let s = stats[tool] else { return 0 }
        let total = s.success + s.failure
        return total == 0 ? 0 : Double(s.success) / Double(total)
    }

    func avgLatency(_ tool: String) -> TimeInterval {
        guard let s = stats[tool] else { return 0 }
        let total = s.success + s.failure
        return total == 0 ? 0 : s.latency / Double(total)
    }

    func health(_ tool: String) -> ToolHealth {
        if blocked.contains(tool) { return .blocked }
        guard let s = stats[tool], s.success + s.failure > 0 else { return .unknown }
        switch successRate(tool) {
        case 0.8...: return .healthy
        case 0.5..<0.8: return .degraded
        default: return .disabled
        }
    }
}

/// Maps objectives to the tools (and thus permissions) they may use (spec §53).
struct CapabilityMatrix: Sendable {

    private var map: [String: Set<String>] = [:]

    mutating func allow(objectiveKind: String, tools: [String]) {
        map[objectiveKind, default: []].formUnion(tools)
    }

    func allowedTools(for objectiveKind: String) -> [String] {
        Array(map[objectiveKind] ?? [])
    }

    func isAllowed(tool: String, for objectiveKind: String) -> Bool {
        map[objectiveKind]?.contains(tool) ?? false
    }
}
