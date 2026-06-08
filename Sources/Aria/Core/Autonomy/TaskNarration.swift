import Foundation

/// Turns a plan step's summary into a short, natural spoken line for the play-by-play
/// Aria says as she works ("Searching the web…", "Saving your note…"). Present-continuous
/// so it sounds like she's doing it right now, capped so it stays a quick aside, not a
/// speech. Pure + deterministic — no model call, no quota.
enum TaskNarration {
    /// Leading imperative verb → present-continuous, so "Search the web" → "Searching the web".
    private static let continuous: [String: String] = [
        "search": "Searching", "open": "Opening", "write": "Writing", "save": "Saving",
        "create": "Creating", "find": "Finding", "read": "Reading", "send": "Sending",
        "type": "Typing", "click": "Clicking", "run": "Running", "check": "Checking",
        "look": "Looking", "get": "Getting", "make": "Making", "summarize": "Summarizing",
        "fetch": "Fetching", "download": "Downloading", "delete": "Deleting", "add": "Adding",
        "compose": "Composing", "draft": "Drafting", "schedule": "Scheduling", "set": "Setting",
        "play": "Playing", "close": "Closing", "copy": "Copying", "move": "Moving",
        "list": "Listing", "build": "Building", "fix": "Fixing", "update": "Updating",
        "remember": "Noting", "calculate": "Calculating", "translate": "Translating"
    ]

    /// The spoken form of a step summary. Empty string for an empty summary (caller skips).
    static func spoken(for summary: String) -> String {
        var s = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        let split = s.split(separator: " ", maxSplits: 1).map(String.init)
        if let first = split.first?.lowercased(),
           let cont = continuous[first.trimmingCharacters(in: .punctuationCharacters)] {
            s = split.count > 1 ? "\(cont) \(split[1])" : cont
        }

        if s.count > 60 { s = String(s.prefix(60)).trimmingCharacters(in: .whitespaces) + "…" }
        let last = s.last
        if last != "." && last != "…" && last != "!" && last != "?" { s += "." }
        return s
    }
}
