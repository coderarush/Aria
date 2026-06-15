import Foundation

/// Scans recent Gmail for commitments and action items the user has made.
struct EmailTaskTool: AriaTool {
    static let name = "email_tasks"
    static let description = "Scan recent Gmail for commitments, pending tasks, and action items. Optional input: {limit} — number of emails to check (default 10)."
    static let paramHints: [String: String] = [
        "limit": "Number of recent emails to scan (default 10)"
    ]

    private let store: ConnectorStore
    private let connector: GoogleConnector
    private let gemini: GeminiClient
    private let extractor: EmailTaskExtractor

    init(store: ConnectorStore = .shared,
         connector: GoogleConnector = GoogleConnector(),
         gemini: GeminiClient = GeminiClient(),
         extractor: EmailTaskExtractor = EmailTaskExtractor()) {
        self.store = store
        self.connector = connector
        self.gemini = gemini
        self.extractor = extractor
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let token = await store.validAccessToken(.google) else {
            return .ok("Gmail isn't connected yet. Connect Gmail in the app first (Settings → Connectors → Google), then ask me again.")
        }

        let limit = input["limit"].flatMap { Int($0) } ?? 10

        let messages: [GoogleConnector.GmailMessageSummary]
        do {
            messages = try await connector.recentGmail(accessToken: token, maxResults: limit)
        } catch {
            return .ok("Couldn't reach Gmail right now. Your connection may need to be re-authorized in the app (Settings → Connectors → Google).")
        }

        guard !messages.isEmpty else {
            return .ok("No recent emails found.")
        }

        // Convert messages to email strings for extractor
        let emailStrings = messages.map { m in
            "Subject: \(m.subject)\nFrom: \(m.from)\n\nBody: \(m.snippet)"
        }

        let tasks: [ExtractedTask]
        do {
            tasks = try await extractor.extract(emails: emailStrings) { prompt in
                try await gemini.generateText(prompt: prompt)
            }
        } catch {
            return .ok("Couldn't parse tasks from emails right now.")
        }

        guard !tasks.isEmpty else {
            return .ok("No commitments found in recent emails.")
        }

        let lines = tasks.enumerated().map { idx, task -> String in
            var line = "\(idx + 1). \(task.commitment) (from: \(task.source))"
            if let deadline = task.deadline {
                line += " — deadline: \(deadline)"
            }
            return line
        }
        return .ok("Commitments found in recent emails:\n\(lines.joined(separator: "\n"))")
    }
}
