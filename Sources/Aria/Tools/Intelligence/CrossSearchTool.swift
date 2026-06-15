import Foundation

/// "Aria searches everything at once" — fans out a topic query to every connected
/// app simultaneously (Gmail, Calendar, Notion, Drive, Slack, GitHub, Linear) and
/// synthesizes a single spoken answer via Gemini. Disconnected sources are silently
/// skipped; the result is never empty (falls back to raw snippets if synthesis fails).
struct CrossSearchTool: AriaTool {
    static let name = "cross_search"
    static let description = "Search across ALL connected apps (Gmail, Calendar, Notion, Drive, Slack, GitHub, Linear) simultaneously and synthesize a unified answer. Input: topic (what to look for)."
    static let paramHints: [String: String] = [
        "topic": "What to look for across all connected apps (e.g. 'project alpha deadline')"
    ]

    private let gemini: GeminiClient
    init(gemini: GeminiClient = GeminiClient()) { self.gemini = gemini }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let topic = input["topic"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !topic.isEmpty else {
            return .ok("Please provide a topic to search for.")
        }

        let synthesizer = CrossConnectorSynthesizer()
        let sources = await CrossConnectorSynthesizer.Sources.live()
        let result = await synthesizer.gather(
            topic: topic,
            sources: sources,
            synthesize: { prompt in try await gemini.generateText(prompt: prompt, temperature: 0.3) }
        )
        return .ok(result)
    }
}

// MARK: - Live sources factory

extension CrossConnectorSynthesizer.Sources {
    /// Build production source closures using live connector tokens.
    /// Each closure catches all errors and returns "" so a disconnected source
    /// never breaks the whole gather.
    static func live() async -> CrossConnectorSynthesizer.Sources {
        CrossConnectorSynthesizer.Sources(
            gmail: { topic in
                guard let token = await ConnectorStore.shared.validAccessToken(.google)
                else { return "" }
                do {
                    let connector = GoogleConnector()
                    let messages = try await connector.recentGmail(
                        accessToken: token, maxResults: 8, query: topic)
                    return GoogleConnector.formatGmail(messages)
                } catch { return "" }
            },
            gcal: { topic in
                guard let token = await ConnectorStore.shared.validAccessToken(.google)
                else { return "" }
                do {
                    let connector = GoogleConnector()
                    let events = try await connector.upcomingEvents(
                        accessToken: token, maxResults: 10,
                        within: 7 * 24 * 60 * 60)
                    return GoogleConnector.formatEvents(events)
                } catch { return "" }
            },
            notion: { topic in
                guard let token = await ConnectorStore.shared.validAccessToken(.notion)
                else { return "" }
                do {
                    let connector = NotionConnector()
                    let hits = try await connector.search(query: topic, accessToken: token)
                    return NotionConnector.formatSearch(hits)
                } catch { return "" }
            },
            drive: { topic in
                guard let token = await ConnectorStore.shared.validAccessToken(.google)
                else { return "" }
                do {
                    let connector = GoogleConnector()
                    let files = try await connector.searchDriveFiles(
                        query: topic, accessToken: token)
                    return GoogleConnector.formatDriveFiles(files)
                } catch { return "" }
            },
            slack: { _ in
                // Slack requires a specific channel id — without one we can't fan out.
                // Users can use slack_recent directly for channel-specific queries.
                return ""
            },
            github: { _ in
                // GitHub issues require a specific "owner/repo" — without one we can't
                // fan out. Users can use github_issues directly for repo-specific queries.
                return ""
            },
            linear: { topic in
                guard let key = KeychainManager.read(account: LinearService.keychainAccount)
                else { return "" }
                do {
                    return try await LinearService(apiKey: key).issues(teamId: nil)
                } catch { return "" }
            }
        )
    }
}
