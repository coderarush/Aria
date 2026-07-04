import Foundation
import AppKit

/// Zero-LLM instant commands — Aria's answer to "why does biscuit feel faster?".
///
/// Everyday one-shot commands (open an app, set the volume, start a timer, open
/// a site) don't need the model at all. Matching them here and executing
/// directly skips the entire planning round-trip — no system prompt, no tool
/// schemas, no network hop to a model — so they complete the instant you finish
/// speaking, exactly like a hard-coded shortcut.
///
/// Matching is deliberately **conservative** (the biscuit-recipe rule): anything
/// ambiguous, multi-step, or needing reasoning returns nil and falls through to
/// the full agent. A wrong instant-fire is worse than a missed one.
enum QuickCommand {

    enum Action: Equatable {
        case openApp(String)
        case openURL(String)          // fully-formed https URL
        case setVolume(Int)           // 0…100
        case setMuted(Bool)           // true = mute, false = unmute
        case startTimer(seconds: Double, label: String)
    }

    // MARK: Matching

    /// Resolve a command to an instant action, or nil to fall through to the model.
    static func match(_ raw: String) -> Action? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        guard !lower.isEmpty else { return nil }

        // Multi-step / compound phrasing is never an instant command — it needs
        // the planner. (Volume/timer parsing tolerates its own keywords below.)
        let compound = [" and ", " then ", ", then ", " after that ", " also "]
        let isCompound = compound.contains { lower.contains($0) }

        if let v = matchVolume(lower) { return v }              // "set volume to 40", "mute"
        if !isCompound, let t = matchTimer(lower) { return t }  // "timer for 10 minutes"
        if !isCompound, let u = matchURL(lower) { return u }    // "open github.com"
        if !isCompound, let a = matchOpenApp(lower, original: text) { return a }  // "open Spotify"
        return nil
    }

    // MARK: Volume

    private static func matchVolume(_ lower: String) -> Action? {
        // Mute / unmute.
        if ["mute", "mute the volume", "mute volume", "be quiet", "silence",
            "shut up", "quiet"].contains(lower) { return .setMuted(true) }
        if ["unmute", "unmute the volume", "unmute volume", "sound on"].contains(lower) {
            return .setMuted(false)
        }

        // Must be talking about volume to set a level.
        guard lower.contains("volume") else { return nil }
        // Reject anything that isn't purely a volume instruction (e.g. "what's my volume").
        let allowed = Set(["set", "the", "volume", "to", "at", "percent", "%", "please",
                           "turn", "make", "it", "of", "output", "sound", "up", "down",
                           "louder", "quieter", "max", "maximum", "full", "half", "min",
                           "minimum", "mute", "all", "the", "way"])
        let words = lower.split(whereSeparator: { $0 == " " || $0 == "%" }).map(String.init)

        // Relative words with no number.
        if lower.contains("max") || lower.contains("full") || lower.contains("all the way") {
            return .setVolume(100)
        }
        if lower.contains("half") { return .setVolume(50) }
        if lower.contains("min") { return .setVolume(0) }

        // Find an explicit number or number-word.
        var level: Int?
        for w in words {
            if let n = Int(w) { level = n; break }
            if let n = numberWord(w) { level = n; break }
        }
        guard let value = level else {
            // "volume up/down" without a number: nudge by 10.
            if lower.contains("up") || lower.contains("louder") { return .setVolume(-1) }   // sentinel: up
            if lower.contains("down") || lower.contains("quieter") { return .setVolume(-2) } // sentinel: down
            return nil
        }
        // Every non-number word must be an allowed volume word — else it's a
        // richer request ("set volume to 40 then play music" is caught by compound).
        for w in words where Int(w) == nil && numberWord(w) == nil {
            guard allowed.contains(w) else { return nil }
        }
        return .setVolume(min(100, max(0, value)))
    }

    // MARK: Timer

    private static func matchTimer(_ lower: String) -> Action? {
        // Only bare "timer for <duration>" — reminders that carry content
        // ("remind me to call mom in 10 minutes") need the model.
        guard lower.contains("timer") else { return nil }
        // Grab the text after "for" (or after "timer").
        let afterFor: String
        if let r = lower.range(of: " for ") { afterFor = String(lower[r.upperBound...]) }
        else if let r = lower.range(of: "timer ") { afterFor = String(lower[r.upperBound...]) }
        else { return nil }
        let duration = afterFor
            .replacingOccurrences(of: "please", with: "")
            .trimmingCharacters(in: .whitespaces)
        // Convert number-words to digits for the duration parser.
        let normalized = normalizeNumberWords(duration)
        guard let seconds = TimerCenter.parseDuration(normalized), seconds > 0 else { return nil }
        return .startTimer(seconds: seconds, label: "\(TimerCenter.format(seconds)) timer")
    }

    // MARK: Open URL

    private static func matchURL(_ lower: String) -> Action? {
        let openers = ["open ", "go to ", "goto ", "visit ", "navigate to ", "launch ", "browse to "]
        guard let opener = openers.first(where: { lower.hasPrefix($0) }) else { return nil }
        var host = String(lower.dropFirst(opener.count)).trimmingCharacters(in: .whitespaces)
        host = host.replacingOccurrences(of: "please", with: "").trimmingCharacters(in: .whitespaces)
        // A single token that looks like a domain: has a dot, a real TLD, no spaces.
        guard !host.contains(" "), host.contains(".") else { return nil }
        // Strip an existing scheme, validate the TLD, then re-form as https.
        var bare = host
        for scheme in ["https://", "http://"] where bare.hasPrefix(scheme) {
            bare = String(bare.dropFirst(scheme.count))
        }
        let hostPart = bare.split(separator: "/").first.map(String.init) ?? bare
        guard let dot = hostPart.lastIndex(of: "."), dot < hostPart.endIndex else { return nil }
        let tld = hostPart[hostPart.index(after: dot)...]
        guard tld.count >= 2, tld.count <= 24, tld.allSatisfy({ $0.isLetter }) else { return nil }
        return .openURL("https://\(bare)")
    }

    // MARK: Open app

    private static func matchOpenApp(_ lower: String, original: String) -> Action? {
        let openers = ["open ", "launch ", "start ", "fire up ", "boot up "]
        guard let opener = openers.first(where: { lower.hasPrefix($0) }) else { return nil }
        // Words that mean this isn't a plain app launch.
        let disqualifiers = ["http", "www.", ".com", ".org", ".net", "search", "play ",
                             "tab", "window", " to ", " for ", " in ", " on ", "?",
                             "volume", "timer", "remind", "file", "folder", "settings",
                             "preferences", "the "]
        let namePart = String(original.dropFirst(opener.count)).trimmingCharacters(in: .whitespaces)
        let nameLower = namePart.lowercased()
        guard !namePart.isEmpty else { return nil }
        for bad in disqualifiers where nameLower.contains(bad) { return nil }
        // App names are short (1–3 words: "Spotify", "Google Chrome", "Activity Monitor").
        guard namePart.split(separator: " ").count <= 3 else { return nil }
        return .openApp(namePart)
    }

    // MARK: Number words

    private static let numberWords: [String: Int] = [
        "zero": 0, "ten": 10, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90, "hundred": 100,
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9,
    ]

    static func numberWord(_ w: String) -> Int? { numberWords[w] }

    /// Replace spelled-out numbers with digits so a duration parser can read them.
    static func normalizeNumberWords(_ text: String) -> String {
        text.split(separator: " ").map { word -> String in
            let key = word.lowercased()
            if let n = numberWords[key] { return String(n) }
            return String(word)
        }.joined(separator: " ")
    }

    // MARK: Execution (zero model calls)

    /// Perform an instant action and return a short spoken confirmation.
    static func run(_ action: Action) async -> String {
        switch action {
        case .openApp(let name):
            let result = try? await OpenAppTool().run(input: ["name": name])
            return result?.output ?? "Opened \(name)."
        case .openURL(let url):
            if let u = URL(string: url) {
                await MainActor.run { NSWorkspace.shared.open(u) }
                let host = u.host ?? url
                return "Opened \(host)."
            }
            return "That doesn't look like a valid address."
        case .setVolume(let sentinel):
            return await setVolume(sentinel)
        case .setMuted(let muted):
            _ = try? await ScriptRunner().run(
                code: "set volume output muted \(muted)", language: .applescript, timeout: 8)
            return muted ? "Muted." : "Unmuted."
        case .startTimer(let seconds, let label):
            await TimerCenter.shared.start(seconds: seconds, label: label)
            return "Timer set — I'll let you know in \(TimerCenter.format(seconds))."
        }
    }

    private static func setVolume(_ value: Int) async -> String {
        let runner = ScriptRunner()
        // Sentinels for relative nudges (no explicit number given).
        if value == -1 || value == -2 {
            let delta = value == -1 ? 10 : -10
            let script = """
            set cur to output volume of (get volume settings)
            set new to cur + (\(delta))
            if new > 100 then set new to 100
            if new < 0 then set new to 0
            set volume output muted false
            set volume output volume new
            return new
            """
            let out = try? await runner.run(code: script, language: .applescript, timeout: 8)
            let level = out?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return level.isEmpty ? "Adjusted the volume." : "Volume \(level)."
        }
        let level = min(100, max(0, value))
        _ = try? await runner.run(
            code: "set volume output muted false\nset volume output volume \(level)",
            language: .applescript, timeout: 8)
        return level == 0 ? "Volume off." : "Volume \(level)."
    }
}
