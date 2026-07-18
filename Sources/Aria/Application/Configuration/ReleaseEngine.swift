import Foundation

/// Release channels (spec §122).
enum ReleaseChannel: String, Sendable { case internalBuild, alpha, beta, stable }

/// Manages releases (spec §122): channel promotion/rollback, a global kill
/// switch, and per-feature gates.
actor ReleaseEngine {

    private(set) var channel: ReleaseChannel
    private var killed = false
    private var gates: [String: Bool] = [:]

    init(channel: ReleaseChannel = .internalBuild) {
        self.channel = channel
    }

    func promote(to channel: ReleaseChannel) { self.channel = channel }
    func rollback(to channel: ReleaseChannel) { self.channel = channel }

    func killSwitch() { killed = true }
    func isLive() -> Bool { !killed }

    func setGate(_ name: String, _ open: Bool) { gates[name] = open }
    func isGateOpen(_ name: String) -> Bool { gates[name] ?? false }
}
