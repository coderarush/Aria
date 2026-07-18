import Foundation

/// A structured end-of-day summary.
struct DailyDigest: Codable, Sendable {
    var date: String
    var summary: String           // 2-3 sentence overview
    var accomplishments: [String] // what you did today
    var overdueItems: [String]    // follow-ups + missed reminders
    var tomorrowPreview: String   // what's coming tomorrow
}

/// Builds a `DailyDigest` by prompting the model with today's timeline,
/// overdue follow-ups, and tomorrow's calendar. Never throws — always
/// returns a usable digest even if the model call fails.
struct DigestEngine: Sendable {

    func generate(
        timeline: String,
        followUps: String,
        tomorrowCalendar: String,
        synthesize: @Sendable (String) async throws -> String
    ) async -> DailyDigest {
        let fallback = DailyDigest(
            date: "today",
            summary: "Here's your end-of-day summary.",
            accomplishments: [],
            overdueItems: [],
            tomorrowPreview: tomorrowCalendar
        )

        let prompt = """
You are an end-of-day digest engine. Create a structured daily digest.
Return ONLY JSON:
{"date":"today","summary":"2-3 sentence overview of the day","accomplishments":["..."],"overdueItems":["..."],"tomorrowPreview":"what's coming tomorrow"}

Today's activity: \(timeline)
Overdue follow-ups: \(followUps)
Tomorrow's calendar: \(tomorrowCalendar)
"""

        do {
            let raw = try await synthesize(prompt)
            // Strip markdown code fences if present
            var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("```") {
                let lines = text.components(separatedBy: "\n")
                text = lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let data = text.data(using: .utf8),
                  let digest = try? JSONDecoder().decode(DailyDigest.self, from: data),
                  !digest.summary.isEmpty else {
                return fallback
            }
            return digest
        } catch {
            return fallback
        }
    }
}
