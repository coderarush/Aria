import Foundation

struct LectureStartTool: AriaTool {
    static let name = "lecture_start"
    static let description = "Start live lecture note-taking. Aria listens and builds structured notes in real time. Optional input: title."
    static let paramHints: [String: String] = ["title": "Optional title for the lecture notes."]

    private let gemini: GeminiClient
    init(gemini: GeminiClient = GeminiClient()) { self.gemini = gemini }

    func run(input: [String: String]) async throws -> ToolResult {
        let title = input["title"]
        do {
            try await LectureSession.shared.start(
                title: title,
                synthesize: { [gemini] prompt in try await gemini.generateText(prompt: prompt, temperature: 0.2) }
            )
        } catch AmbientTranscriptionError.permissionDenied {
            return .fail("Microphone or speech recognition permission denied. Please grant access in System Settings.")
        } catch AmbientTranscriptionError.recognizerUnavailable {
            return .fail("Speech recognizer is unavailable on this device.")
        } catch {
            return .fail("Failed to start lecture recording: \(error.localizedDescription)")
        }
        let suffix = title.map { " for '\($0)'" } ?? ""
        return .ok("Lecture note-taking started\(suffix). I'll build your notes as the lecture progresses.")
    }
}

struct LectureStopTool: AriaTool {
    static let name = "lecture_stop"
    static let description = "Stop lecture note-taking and finalize notes. Returns a summary."

    private let gemini: GeminiClient
    init(gemini: GeminiClient = GeminiClient()) { self.gemini = gemini }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let note = await LectureSession.shared.stop(
            synthesize: { [gemini] prompt in try await gemini.generateText(prompt: prompt, temperature: 0.2) }
        ) else {
            return .ok("No lecture recording in progress.")
        }
        return .ok("Lecture notes saved: '\(note.title)' — \(note.outline.count) sections, \(note.keyTerms.count) key terms. \(note.summary)")
    }
}
