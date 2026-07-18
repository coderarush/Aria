import Foundation

/// The lifecycle states owned by ``AriaRuntime`` (spec §10).
///
/// Raw values are stable strings so they can travel as event payloads and be
/// persisted across launches without a separate mapping table.
enum RuntimeState: String, Sendable, Equatable, CaseIterable {
    case booting
    case idle
    case thinking
    case executing
    case waiting
    case recovering
    case paused
}
