import Foundation

/// What a device is for in the mesh (spec §77).
enum DeviceRole: String, Sendable { case execution, control, awareness, presence }

/// A device participating in the mesh.
struct MeshDevice: Identifiable, Sendable {
    let kind: SurfaceKind
    var role: DeviceRole
    var connected: Bool
    var id: SurfaceKind { kind }
}

/// Makes Aria portable across devices (spec §77): discover/connect/handoff/
/// sync/recover. Roles: Mac executes, Phone controls, Watch is awareness, Glass
/// is presence. Execution stays on the Mac — other devices never execute.
actor DeviceMesh {

    private var devices: [SurfaceKind: MeshDevice] = [:]

    /// The canonical role for each device kind (spec §77).
    static func defaultRole(for kind: SurfaceKind) -> DeviceRole {
        switch kind {
        case .desktop: return .execution
        case .phone: return .control
        case .watch: return .awareness
        case .glass: return .presence
        }
    }

    func discover(_ kind: SurfaceKind, role: DeviceRole? = nil) {
        devices[kind] = MeshDevice(kind: kind, role: role ?? Self.defaultRole(for: kind), connected: false)
    }

    func connect(_ kind: SurfaceKind) {
        if devices[kind] == nil { discover(kind) }
        devices[kind]?.connected = true
    }

    func disconnect(_ kind: SurfaceKind) { devices[kind]?.connected = false }

    func connected() -> [MeshDevice] { devices.values.filter(\.connected) }

    func device(_ kind: SurfaceKind) -> MeshDevice? { devices[kind] }
}
