import Foundation

/// Accumulates streamed text and emits complete, speakable sentence chunks as
/// soon as they're available, so TTS can start on the first sentence while the
/// rest is still streaming. A length cap forcibly emits at a word boundary so a
/// long run-on doesn't stall speech.
struct SentenceChunker {
    private var buffer = ""
    let maxChunk: Int

    init(maxChunk: Int = 200) { self.maxChunk = maxChunk }

    /// Append streamed text; return any newly completed chunks (in order).
    mutating func push(_ text: String) -> [String] {
        buffer += text
        var out: [String] = []
        while let chunk = nextChunk() { out.append(chunk) }
        return out
    }

    /// Return whatever is left (e.g. a final sentence with no terminator) and clear.
    mutating func flush() -> String {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest
    }

    private mutating func nextChunk() -> String? {
        // 1. Prefer a sentence terminator.
        if let idx = buffer.firstIndex(where: { ".!?".contains($0) }) {
            let end = buffer.index(after: idx)
            let chunk = String(buffer[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[end...])
            return chunk.isEmpty ? nextChunk() : chunk
        }
        // 2. Length cap: emit up to the last word boundary before the cap.
        if buffer.count >= maxChunk, let space = buffer[..<buffer.index(buffer.startIndex, offsetBy: maxChunk)].lastIndex(of: " ") {
            let chunk = String(buffer[..<space]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[buffer.index(after: space)...])
            return chunk.isEmpty ? nil : chunk
        }
        return nil
    }
}
