import Foundation

/// Where an experience can be rendered (spec §64). Glass is listed but does not
/// exist yet — it inherits capability, it is not built here (spec §64/§67).
enum SurfaceKind: String, Sendable, CaseIterable { case desktop, phone, watch, glass }

/// The compressed state a surface renders (spec §65 ContextStream output):
/// objective, status, attention, context, memory — never execution.
struct StreamState: Sendable {
    var objective: String?
    var status: String
    var attention: String
    var context: String
    var memory: [String]
}

/// A renderable surface (spec §64 SurfaceProtocol). Surfaces present state and
/// hand off between devices; they never execute — execution stays in Runtime.
protocol SurfaceProtocol: Sendable {
    var kind: SurfaceKind { get }
    func render(_ state: StreamState) async
    func update(_ state: StreamState) async
    func dismiss() async
    func handoff(to: SurfaceKind) async
}

/// Coordinates the registered surfaces (spec §64 ExperienceLayer). Broadcasts
/// compressed state to every surface and brokers handoffs. Deliberately exposes
/// no execution capability.
actor ExperienceLayer {

    private var surfaces: [SurfaceKind: any SurfaceProtocol] = [:]

    func register(_ surface: any SurfaceProtocol) {
        surfaces[surface.kind] = surface
    }

    var registered: [SurfaceKind] { Array(surfaces.keys) }

    /// Render the latest state on every surface.
    func broadcast(_ state: StreamState) async {
        for surface in surfaces.values {
            await surface.render(state)
        }
    }

    /// Hand the active experience from one surface to another.
    func handoff(from: SurfaceKind, to: SurfaceKind) async {
        await surfaces[from]?.handoff(to: to)
    }
}
