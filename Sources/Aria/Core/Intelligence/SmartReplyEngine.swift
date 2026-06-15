import Foundation

/// A single suggested email reply with a tone label.
struct SmartReply: Codable, Sendable, Equatable {
    var text: String   // the reply text
    var tone: String   // "brief" | "friendly" | "formal"
}

/// Errors from SmartReplyEngine.
enum SmartReplyError: Error, Equatable {
    case parseFailure
}

/// Generates three tone-varied reply options for an incoming email using an
/// injected LLM synthesize closure. Sendable and stateless.
struct SmartReplyEngine: Sendable {

    /// Generate exactly 3 smart replies for an email. Throws `.parseFailure` if
    /// the model output can't be parsed or returns fewer than 3 items.
    func generate(
        emailSubject: String,
        emailBody: String,
        from: String,
        synthesize: @Sendable (String) async throws -> String
    ) async throws -> [SmartReply] {
        let prompt = """
Generate exactly 3 short email reply options for this email. Vary the tone: one brief, one friendly, one formal.
Return ONLY JSON array: [{"text":"...","tone":"brief"},{"text":"...","tone":"friendly"},{"text":"...","tone":"formal"}]
Keep each reply under 3 sentences.

Email from: \(from)
Subject: \(emailSubject)
Body: \(emailBody)
"""
        let raw = try await synthesize(prompt)

        // Extract the JSON array from the response.
        guard let startIdx = raw.firstIndex(of: "["),
              let endIdx = raw.lastIndex(of: "]") else {
            throw SmartReplyError.parseFailure
        }
        let jsonString = String(raw[startIdx...endIdx])
        guard let data = jsonString.data(using: .utf8) else {
            throw SmartReplyError.parseFailure
        }

        let decoded: [SmartReply]
        do {
            decoded = try JSONDecoder().decode([SmartReply].self, from: data)
        } catch {
            throw SmartReplyError.parseFailure
        }

        guard decoded.count >= 3 else {
            throw SmartReplyError.parseFailure
        }

        return Array(decoded.prefix(3))
    }
}
