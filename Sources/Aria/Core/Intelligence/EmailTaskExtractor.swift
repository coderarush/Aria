import Foundation

struct ExtractedTask: Codable, Sendable, Equatable {
    var commitment: String
    var deadline: String?
    var source: String   // email subject
}

enum EmailTaskError: Error {
    case parseFailure
}

struct EmailTaskExtractor: Sendable {
    func extract(
        emails: [String],
        synthesize: @Sendable (String) async throws -> String
    ) async throws -> [ExtractedTask] {
        let emailsText = emails.joined(separator: "\n---\n")
        let prompt = """
You are a task extractor. Read these emails and find any commitment or pending task the recipient has.
Look for: "I will", "I'll", deadlines, action items, follow-ups needed.
Return ONLY JSON array (empty array if none): [{"commitment":"...","deadline":"...","source":"subject"}]
The "deadline" field is optional — omit it if no deadline found.

Emails:
\(emailsText)
"""
        let raw = try await synthesize(prompt)

        // Find JSON array in the response
        guard let startIdx = raw.firstIndex(of: "["),
              let endIdx = raw.lastIndex(of: "]"), startIdx <= endIdx else {
            throw EmailTaskError.parseFailure
        }
        let jsonString = String(raw[startIdx...endIdx])
        guard let data = jsonString.data(using: .utf8) else {
            throw EmailTaskError.parseFailure
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([ExtractedTask].self, from: data)
        } catch {
            throw EmailTaskError.parseFailure
        }
    }
}
