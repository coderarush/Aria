import Foundation

/// Speaks a stream of sentence chunks in order, one at a time. Decouples the
/// ordering/queue logic (unit-tested) from the actual TTS via injectable
/// closures, so the real wiring uses VoiceEngine and tests use spies.
@MainActor
final class StreamingVoice {
    private let speakChunk: (String) -> Void
    private let stopAll: () -> Void
    private var queue: [String] = []
    private(set) var isSpeaking = false

    var onAllFinished: (() -> Void)?

    init(speakChunk: @escaping (String) -> Void, stopAll: @escaping () -> Void) {
        self.speakChunk = speakChunk
        self.stopAll = stopAll
    }

    func enqueue(_ chunk: String) {
        let c = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return }
        queue.append(c)
        if !isSpeaking { speakNext() }
    }

    /// The current chunk finished playing (wired to VoiceEngine.onChunkFinished).
    func chunkDidFinish() {
        guard isSpeaking else { return }
        if queue.isEmpty { isSpeaking = false; onAllFinished?() }
        else { speakNext() }
    }

    func stop() {
        queue.removeAll()
        isSpeaking = false
        stopAll()
    }

    private func speakNext() {
        guard !queue.isEmpty else { isSpeaking = false; onAllFinished?(); return }
        let next = queue.removeFirst()
        isSpeaking = true
        speakChunk(next)
    }
}
