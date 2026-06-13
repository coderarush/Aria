import Foundation

/// Pure, testable view-model helpers for the full Aria app window (v1).
///
/// Views stay thin: they call these to sort, snippet and time-stamp the rows
/// they show. Everything here is value-level and side-effect-free so it can be
/// unit-tested without touching disk, the actors, or SwiftUI.
enum AppWindowModel {

    // MARK: Conversations

    /// A flattened, display-ready conversation row built from a `ConversationTurn`.
    struct ConversationRow: Identifiable, Equatable {
        let id: UUID
        let date: Date
        /// One-line snippet for the list (what the user said, falling back to Aria's reply).
        let snippet: String
        /// What the user said (may be empty for a proactive turn).
        let transcript: String
        /// Aria's reply, shown in the detail pane.
        let response: String
    }

    /// Build display rows from raw turns, **most recent first**.
    /// A turn with an empty transcript (e.g. a proactive line) snippets from the reply.
    static func conversationRows(from turns: [ConversationTurn]) -> [ConversationRow] {
        turns
            .sorted { $0.timestamp > $1.timestamp }
            .map { turn in
                let said = turn.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                let reply = turn.responseMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                let snippetSource = said.isEmpty ? reply : said
                return ConversationRow(
                    id: turn.id,
                    date: turn.timestamp,
                    snippet: snippet(snippetSource),
                    transcript: said,
                    response: reply)
            }
    }

    /// Collapse to a single line and cap length for list display.
    static func snippet(_ text: String, max: Int = 80) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.isEmpty { return "Untitled" }
        return oneLine.count <= max ? oneLine : String(oneLine.prefix(max)) + "\u{2026}"
    }

    // MARK: Relative time

    /// Compact relative time for a row — "just now", "5m ago", "3h ago",
    /// "2d ago", else an abbreviated date. Pure given an explicit `reference`.
    static func relativeTime(_ date: Date, reference: Date = Date(),
                             calendar: Calendar = .current) -> String {
        let seconds = reference.timeIntervalSince(date)
        if seconds < 0 { return "just now" }       // clock skew → don't show the future
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: Connectors (v1 placeholder scaffold)

    /// A v1 integration card. `available` is always false in v1 — real OAuth
    /// comes later; the card renders a disabled "Coming soon" Connect button.
    struct Connector: Identifiable, Equatable {
        let id: String
        let name: String
        /// SF Symbol name.
        let icon: String
        /// Whether connecting is wired up yet (always false in v1).
        let available: Bool
    }

    /// The v1 connector catalog — placeholders for the integrations Aria will
    /// support. None are wired to OAuth yet.
    static let connectors: [Connector] = [
        Connector(id: "gmail",    name: "Gmail",           icon: "envelope.fill",          available: false),
        Connector(id: "gcal",     name: "Google Calendar", icon: "calendar",               available: false),
        Connector(id: "notion",   name: "Notion",          icon: "note.text",              available: false),
        Connector(id: "slack",    name: "Slack",           icon: "number",                 available: false),
        Connector(id: "applemail", name: "Apple Mail",     icon: "tray.full.fill",         available: false),
        Connector(id: "icloud",   name: "iCloud",          icon: "icloud.fill",            available: false),
    ]
}
