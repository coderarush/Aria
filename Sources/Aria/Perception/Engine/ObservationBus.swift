import Foundation

/// Async distribution of observations (spec §70), separate from the execution
/// ``EventBus`` so perception traffic never mixes with action traffic.
actor ObservationBus {

    private var continuations: [UUID: AsyncStream<Observation>.Continuation] = [:]
    private var buffer: [Observation] = []
    private let replayBufferSize: Int

    init(replayBufferSize: Int = 256) {
        self.replayBufferSize = max(0, replayBufferSize)
    }

    func publish(_ observation: Observation) {
        buffer.append(observation)
        if buffer.count > replayBufferSize {
            buffer.removeFirst(buffer.count - replayBufferSize)
        }
        for continuation in continuations.values {
            continuation.yield(observation)
        }
    }

    func subscribe() -> AsyncStream<Observation> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
    }

    func replay() -> [Observation] { buffer }

    private func removeSubscriber(_ id: UUID) { continuations[id] = nil }
}
