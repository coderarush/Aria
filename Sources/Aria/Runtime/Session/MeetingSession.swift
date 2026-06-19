import Foundation

struct MeetingNotes: Codable, Sendable, Identifiable {
    let id: UUID
    var title: String
    var date: Date
    var segments: [TranscriptSegment]
    var actionItems: [String]
    var decisions: [String]
    var openQuestions: [String]
    var summary: String
    var durationSeconds: Int

    var formattedTranscript: String {
        segments.map { "[\($0.speakerLabel)] \($0.text)" }.joined(separator: "\n")
    }
}

actor MeetingSession {
    static let shared = MeetingSession()

    enum State: Equatable { case idle, recording }
    private(set) var state: State = .idle

    var onUpdate: (@Sendable (MeetingNotes) async -> Void)?
    var engineFactory: @Sendable () -> AmbientTranscriptionEngine = { AmbientTranscriptionEngine() }

    func configure(engineFactory: (@Sendable () -> AmbientTranscriptionEngine)? = nil) {
        if let ef = engineFactory { self.engineFactory = ef }
    }

    func setStateForTesting(_ state: State) {
        self.state = state
    }

    var engine: AmbientTranscriptionEngine?
    var note: MeetingNotes?
    var turnCount: Int = 1
    var startTime: Date = Date()
    var storedSynthesize: (@Sendable (String) async throws -> String)?

    // MARK: - Public API

    func start(title: String?, synthesize: @escaping @Sendable (String) async throws -> String) async throws {
        guard state == .idle else { return }

        let newEngine = engineFactory()
        engine = newEngine
        turnCount = 1
        startTime = Date()
        storedSynthesize = synthesize

        let resolvedTitle = title ?? "Meeting \(DateFormatter.meetingDate.string(from: startTime))"
        note = MeetingNotes(
            id: UUID(),
            title: resolvedTitle,
            date: startTime,
            segments: [],
            actionItems: [],
            decisions: [],
            openQuestions: [],
            summary: "",
            durationSeconds: 0
        )

        try await newEngine.start(locale: "en-US", chunkInterval: 30, silenceGap: 1.5) { [weak self] chunk, _ in
            guard let self else { return }
            await self.processChunk(chunk)
        }

        state = .recording
    }

    func stop() async -> MeetingNotes? {
        guard state != .idle else { return nil }

        await engine?.stop()
        engine = nil
        state = .idle

        guard var finalNote = note else { return nil }
        note = nil

        guard !finalNote.segments.isEmpty else { return nil }

        // Final synthesis
        if let synthesize = storedSynthesize {
            let prompt = """
            Analyze this meeting transcript and extract structured information.
            Return ONLY JSON:
            {"actionItems":["..."],"decisions":["..."],"openQuestions":["..."],"summary":"3 sentences"}

            Transcript:
            \(finalNote.formattedTranscript.prefix(6000))
            """
            do {
                let raw = try await synthesize(prompt)
                parseMeetingJSON(raw, into: &finalNote)
            } catch {
                finalNote.summary = "Meeting transcript saved. \(finalNote.segments.count) turns recorded."
            }
        } else {
            finalNote.summary = "Meeting transcript saved. \(finalNote.segments.count) turns recorded."
        }

        storedSynthesize = nil
        finalNote.durationSeconds = Int(Date().timeIntervalSince(startTime))
        saveNote(finalNote, subdir: "Meetings", filename: "\(DateFormatter.meetingDate.string(from: finalNote.date))-\(finalNote.title.sanitizedFilename).json")
        return finalNote
    }

    // MARK: - Internal (accessible in tests)

    func processChunk(_ chunk: String) async {
        guard var currentNote = note else { return }

        let segment = TranscriptSegment(
            speakerLabel: "Turn \(turnCount)",
            text: chunk,
            timestamp: Date()
        )
        currentNote.segments.append(segment)
        turnCount += 1

        note = currentNote
        let noteSnapshot = currentNote
        Task { await self.onUpdate?(noteSnapshot) }
    }

    // MARK: - Private helpers

    private func parseMeetingJSON(_ raw: String, into finalNote: inout MeetingNotes) {
        guard let startIdx = raw.firstIndex(of: "{"),
              let endIdx = raw.lastIndex(of: "}") else {
            finalNote.summary = "Meeting transcript saved. \(finalNote.segments.count) turns recorded."
            return
        }

        let jsonString = String(raw[startIdx...endIdx])
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            finalNote.summary = "Meeting transcript saved. \(finalNote.segments.count) turns recorded."
            return
        }

        finalNote.actionItems = obj["actionItems"] as? [String] ?? []
        finalNote.decisions = obj["decisions"] as? [String] ?? []
        finalNote.openQuestions = obj["openQuestions"] as? [String] ?? []
        finalNote.summary = obj["summary"] as? String ?? "Meeting transcript saved. \(finalNote.segments.count) turns recorded."
    }

    private func saveNote<T: Encodable>(_ note: T, subdir: String, filename: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Aria Notes/\(subdir)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(note) {
            try? data.write(to: dir.appendingPathComponent(filename), options: .atomic)
        }
    }
}

// MARK: - Private helpers

private extension DateFormatter {
    static let meetingDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

private extension String {
    var sanitizedFilename: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        return self
            .components(separatedBy: allowed.inverted)
            .joined(separator: "")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
            .prefix(60)
            .description
    }
}
