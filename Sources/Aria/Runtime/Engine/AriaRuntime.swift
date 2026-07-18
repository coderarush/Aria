import Foundation

/// The single source of authority for runtime state (spec §10).
///
/// Responsibilities: owns the lifecycle state machine, routes execution, and
/// emits a `runtimeStateChanged` event on every transition. Implemented as an
/// actor so there is exactly one authority and no global mutable state.
actor AriaRuntime {

    private(set) var state: RuntimeState = .booting
    private let eventBus: EventBus

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    // MARK: - Lifecycle (spec §10 methods)

    /// Bring the runtime up from `booting` to `idle`.
    func start() async { await transition(to: .idle) }

    /// Tear the runtime back down to its pre-start `booting` state.
    func stop() async { await transition(to: .booting) }

    /// Pause all activity. Resumable via ``resume()``.
    func suspend() async { await transition(to: .paused) }

    /// Resume from `paused` back to `idle`.
    func resume() async { await transition(to: .idle) }

    /// Run the recovery flow, returning to `idle` when stable.
    func recover() async {
        await transition(to: .recovering)
        await transition(to: .idle)
    }

    /// Drive the runtime into an arbitrary working state (e.g. the execution
    /// engine entering `.executing` or `.waiting`).
    func enter(_ newState: RuntimeState) async { await transition(to: newState) }

    // MARK: - Event routing

    /// Forward an event to the shared ``EventBus``.
    func emit(_ event: AriaEvent) async { await eventBus.emit(event) }

    // MARK: - Internals

    private func transition(to newState: RuntimeState) async {
        let previous = state
        state = newState
        await eventBus.emit(AriaEvent(
            kind: .runtimeStateChanged,
            source: "AriaRuntime",
            payload: ["from": previous.rawValue, "to": newState.rawValue]
        ))
    }
}
