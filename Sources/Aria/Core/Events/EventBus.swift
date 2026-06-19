import Foundation

/// The central nervous system of the runtime.
///
/// Spec §12 requirements:
/// - everything emits events
/// - async delivery to any number of subscribers
/// - events are immutable
/// - replay support (a bounded ring of the most recent events)
///
/// Implemented as an actor so emission and subscription are race-free without
/// external locking.
actor EventBus {

    private var continuations: [UUID: AsyncStream<AriaEvent>.Continuation] = [:]
    private var buffer: [AriaEvent] = []
    private let replayBufferSize: Int

    init(replayBufferSize: Int = 512) {
        self.replayBufferSize = max(0, replayBufferSize)
    }

    /// Publish an event to every live subscriber and append it to the replay
    /// ring, evicting the oldest entries past the buffer bound.
    func emit(_ event: AriaEvent) {
        buffer.append(event)
        if buffer.count > replayBufferSize {
            buffer.removeFirst(buffer.count - replayBufferSize)
        }
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    /// Returns an async stream of every event emitted after subscription.
    /// The stream is removed automatically when its consumer is torn down.
    func subscribe() -> AsyncStream<AriaEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
    }

    /// The most recent events, oldest first, up to the replay buffer bound.
    func replay() -> [AriaEvent] { buffer }

    private func removeSubscriber(_ id: UUID) {
        continuations[id] = nil
    }
}
