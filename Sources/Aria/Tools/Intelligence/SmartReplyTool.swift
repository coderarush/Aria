import Foundation

/// Generates three tone-varied email reply suggestions for an incoming email.
struct SmartReplyTool: AriaTool {
    static let name = "smart_reply"
    static let description = "Generate 3 smart reply options (brief, friendly, formal) for an email. Input: {subject}, {body}, {from}."
    static let paramHints: [String: String] = [
        "subject": "Email subject line",
        "body":    "Email body text",
        "from":    "Sender name or address"
    ]

    private let engine: SmartReplyEngine
    private let gemini: GeminiClient

    init(engine: SmartReplyEngine = SmartReplyEngine(),
         gemini: GeminiClient = GeminiClient()) {
        self.engine = engine
        self.gemini = gemini
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let subject = input["subject"] ?? ""
        let body    = input["body"]    ?? ""
        let from    = input["from"]    ?? ""

        let replies: [SmartReply]
        do {
            replies = try await engine.generate(
                emailSubject: subject,
                emailBody: body,
                from: from,
                synthesize: { [gemini] prompt in try await gemini.generateText(prompt: prompt) }
            )
        } catch SmartReplyError.parseFailure {
            return .fail("Couldn't generate smart replies — model returned unexpected output.")
        }

        let subjectLabel = subject.isEmpty ? "(no subject)" : subject
        let lines = replies.enumerated().map { idx, r in
            "\(idx + 1). [\(r.tone)] → \"\(r.text)\""
        }.joined(separator: "\n")

        let output = """
Smart replies for "\(subjectLabel)":

\(lines)

Say "send reply 1" (or 2/3) to send, or "draft reply 2" to edit first.
"""
        return .ok(output)
    }
}
