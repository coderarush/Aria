import Foundation

/// A live stream of compressed runtime state (spec §65): objective, status,
/// attention, context, memory. Presence consumes it now; Glass consumes it
/// later. Carries state only — never execution.
actor ContextStream {

    private var current = StreamState(objective: nil, status: "idle",
                                      attention: "idle", context: "", memory: [])
    private var continuations: [UUID: AsyncStream<StreamState>.Continuation] = [:]

    func publish(_ state: StreamState) {
        current = state
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }

    func latest() -> StreamState { current }

    func subscribe() -> AsyncStream<StreamState> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
    }

    private func removeSubscriber(_ id: UUID) { continuations[id] = nil }
}
