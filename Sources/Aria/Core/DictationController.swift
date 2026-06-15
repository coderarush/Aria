import AppKit

/// System-wide dictation: speak into ANY app's text field and the cleaned-up
/// transcript is typed at the cursor. Distinct from push-to-talk — those words
/// are a command Aria interprets; these words ARE the output, inserted verbatim
/// (lightly cleaned). The capture/STT is reused from the normal voice path; this
/// type only owns the cleanup + insertion, so it stays off the fragile audio code.
@MainActor
final class DictationController {

    /// Lightweight, deterministic cleanup of a raw transcript: trim, collapse
    /// runaway whitespace, drop standalone fillers, capitalize the first letter,
    /// and ensure terminal punctuation. Pure so it's unit-testable; intentionally
    /// conservative (it never rewrites words — that would change meaning).
    nonisolated static func cleanup(_ raw: String) -> String {
        var words = raw
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
        let fillers: Set<String> = ["um", "uh", "umm", "uhh", "er", "err", "ah", "hmm"]
        words.removeAll { w in
            let bare = w.lowercased().trimmingCharacters(in: .punctuationCharacters)
            return fillers.contains(bare)
        }
        var t = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        t = t.prefix(1).uppercased() + t.dropFirst()
        if let last = t.last, !".!?".contains(last) { t += "." }
        return t
    }

    /// Optional AI cleanup: punctuation, capitalization, and obvious mis-hear
    /// fixes — WITHOUT changing wording or meaning. Returns nil on any failure so
    /// the caller falls back to the heuristic clean. Kept short for low latency.
    func aiCleanup(_ raw: String, via client: GeminiClient) async -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let prompt = """
        Rewrite this dictated text with correct punctuation, capitalization, and \
        spacing, fixing only obvious speech-to-text errors. Do NOT change the \
        wording, add content, or answer it — return ONLY the cleaned text.

        \(trimmed)
        """
        guard let out = try? await client.generateText(prompt: prompt, temperature: 0) else { return nil }
        let cleaned = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Insert text at the cursor in the frontmost app by pasting it (the most
    /// reliable cross-app insertion), restoring the user's prior clipboard right
    /// after so dictation never clobbers what they had copied.
    func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        Self.postCommandV()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pb.clearContents()
            if let saved { pb.setString(saved, forType: .string) }
        }
    }

    /// Synthesize ⌘V into the focused app. Rides the same Accessibility trust the
    /// hotkey tap already requires.
    private static func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9   // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
