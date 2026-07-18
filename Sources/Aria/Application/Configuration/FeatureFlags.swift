import Foundation

/// Runtime configuration surface (spec §19): feature flags + the execution
/// environment (local / cloud / hybrid). Unknown flags default to off.
struct FeatureFlags: Sendable {

    enum RuntimeEnvironment: String, Sendable { case local, cloud, hybrid }

    var environment: RuntimeEnvironment
    private var flags: [String: Bool]

    init(environment: RuntimeEnvironment = .hybrid, defaults: [String: Bool] = [:]) {
        self.environment = environment
        self.flags = defaults
    }

    func isEnabled(_ key: String) -> Bool { flags[key] ?? false }

    mutating func set(_ key: String, _ enabled: Bool) { flags[key] = enabled }
}
