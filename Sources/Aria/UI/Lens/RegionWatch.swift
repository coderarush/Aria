import Foundation

/// Decides whether a circled region's content has *meaningfully* changed between
/// two OCR reads — tolerant of the small jitter OCR produces on identical pixels,
/// but firing on a real change (a status flips, a number updates, text appears or
/// disappears). Pure + testable.
enum RegionChange {
    /// Lowercased, whitespace-collapsed form for stable comparison.
    static func normalize(_ s: String) -> String {
        s.lowercased().split { $0.isWhitespace || $0.isNewline }.joined(separator: " ")
    }

    /// True when `to` differs enough from `from` to be worth a notification.
    /// `minJaccard` is the token-overlap floor below which a change counts (default
    /// 0.75 → roughly a quarter of tokens changed, so OCR jitter and one-word edits
    /// stay quiet while real status/number flips fire).
    static func changed(from: String, to: String, minJaccard: Double = 0.75) -> Bool {
        let a = normalize(from), b = normalize(to)
        if a == b { return false }
        if a.isEmpty || b.isEmpty { return a != b }     // appeared / disappeared
        let ta = Set(a.split(separator: " ")), tb = Set(b.split(separator: " "))
        let union = ta.union(tb)
        guard !union.isEmpty else { return false }
        let jaccard = Double(ta.intersection(tb).count) / Double(union.count)
        return jaccard < minJaccard
    }
}

/// Matches "stop watching / stop the walkthrough" — lets the user call off any
/// on-screen activity (region watch, guided walkthrough, markers) without ending
/// the whole conversation. Pure.
enum StopActivityIntent {
    private static let phrases = [
        "stop watching", "stop the watch", "stop watch", "stop the walkthrough",
        "stop the walk through", "cancel the walkthrough", "stop pointing",
        "stop guiding", "stop showing me", "clear the screen", "stop the markers"
    ]
    static func matches(_ command: String) -> Bool {
        let c = command.lowercased()
        return phrases.contains { c.contains($0) }
    }
}

/// Matches an explicit "watch this region" request. Explicit phrasing so it never
/// hijacks a normal sentence containing "watch". Pure.
enum RegionWatchIntent {
    private static let phrases = [
        "watch this", "watch that", "keep an eye on this", "keep an eye on that",
        "tell me when this changes", "tell me when that changes",
        "notify me when this changes", "let me know when this changes",
        "watch this region", "watch for changes"
    ]
    static func matches(_ command: String) -> Bool {
        let c = command.lowercased()
        return phrases.contains { c.contains($0) }
    }
}
