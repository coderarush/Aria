import Foundation

/// The minimal, transparent HUD shown on Glass (spec §80 HUDSurface): objective,
/// status, continue affordance, memory, context. No chat, low attention.
struct HUDState: Sendable {
    var objective: String?
    var status: String
    var canContinue: Bool
    var memory: [String]
    var context: String

    static let empty = HUDState(objective: nil, status: "idle", canContinue: false,
                                memory: [], context: "")
}

/// Glass runtime (spec §79) — software only, works without Glass hardware
/// (spec §86). Consumes context and displays awareness; it has NO execution and
/// NO tools (conforms ``SurfaceProtocol`` for render/update/dismiss/handoff,
/// nothing else).
actor GlassRuntime: SurfaceProtocol {

    enum GlassState: String, Sendable { case idle, aware, listening, displaying, sleeping }

    nonisolated let kind: SurfaceKind = .glass

    private(set) var state: GlassState = .idle
    private(set) var hud: HUDState = .empty

    func render(_ stream: StreamState) async {
        hud = HUDState(objective: stream.objective,
                       status: stream.status,
                       canContinue: stream.objective != nil,
                       memory: stream.memory,
                       context: stream.context)
        state = stream.objective == nil ? .aware : .displaying
    }

    func update(_ stream: StreamState) async { await render(stream) }

    func dismiss() async {
        hud = .empty
        state = .idle
    }

    func handoff(to: SurfaceKind) async {
        state = .sleeping
    }

    func listen() { state = .listening }
    func sleep() { state = .sleeping }
    func wake() { state = .aware }
}
