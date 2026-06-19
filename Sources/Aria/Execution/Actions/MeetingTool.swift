import Foundation

struct MeetingStartTool: AriaTool {
    static let name = "meeting_start"
    static let description = "Start meeting transcription and note-taking. Aria records turns and extracts action items. Optional input: title."
    static let paramHints: [String: String] = ["title": "Optional title for the meeting notes."]

    private let gemini: GeminiClient
    init(gemini: GeminiClient = GeminiClient()) { self.gemini = gemini }

    func run(input: [String: String]) async throws -> ToolResult {
        let title = input["title"]
        do {
            try await MeetingSession.shared.start(
                title: title,
                synthesize: { [gemini] prompt in try await gemini.generateText(prompt: prompt, temperature: 0.2) }
            )
        } catch AmbientTranscriptionError.permissionDenied {
            return .fail("Microphone or speech recognition permission denied. Please grant access in System Settings.")
        } catch AmbientTranscriptionError.recognizerUnavailable {
            return .fail("Speech recognizer is unavailable on this device.")
        } catch {
            return .fail("Failed to start meeting recording: \(error.localizedDescription)")
        }
        let suffix = title.map { " for '\($0)'" } ?? ""
        return .ok("Meeting recording started\(suffix). I'll transcribe turns and extract action items when you stop.")
    }
}

struct MeetingStopTool: AriaTool {
    static let name = "meeting_stop"
    static let description = "Stop meeting recording and finalize notes with action items, decisions, and summary."

    private let gemini: GeminiClient
    init(gemini: GeminiClient = GeminiClient()) { self.gemini = gemini }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let note = await MeetingSession.shared.stop() else {
            return .ok("No meeting recording in progress, or no speech was captured.")
        }
        var parts = ["Meeting notes saved: '\(note.title)' — \(note.segments.count) turns."]
        if !note.actionItems.isEmpty {
            parts.append("Action items: \(note.actionItems.joined(separator: "; "))")
        }
        if !note.summary.isEmpty {
            parts.append(note.summary)
        }
        return .ok(parts.joined(separator: " "))
    }
}
