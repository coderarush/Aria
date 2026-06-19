import Foundation

/// The state transferred between devices on handoff (spec §78).
struct HandoffBundle: Sendable {
    var objectiveID: UUID?
    var memory: [String]
    var attention: String
    var status: String
    var artifacts: [String]
}

/// Transfers context between devices so work resumes instantly (spec §78).
/// A bundle sent to a device is consumed on receive.
actor ContextHandoff {

    private var pending: [SurfaceKind: HandoffBundle] = [:]

    func send(_ bundle: HandoffBundle, to device: SurfaceKind) {
        pending[device] = bundle
    }

    /// Resume on a device, consuming the pending bundle if any.
    func receive(on device: SurfaceKind) -> HandoffBundle? {
        defer { pending[device] = nil }
        return pending[device]
    }
}
