import Foundation

/// ARIA_DEMO_MODE (website constitution requirement): deterministic, repeatable
/// responses for marketing videos, website demos, and investor recordings —
/// never fails mid-take. Launch with:
///
///     ARIA_DEMO_MODE=1 [ARIA_DEMO_SCRIPT=/path/to/script.json] make run
///
/// When enabled, model calls short-circuit to a scripted reply (first script
/// key contained in the prompt wins; custom script file overrides the built-in
/// set). Tools, voice, and UI behave normally — only the model is scripted.
enum DemoMode {

    static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["ARIA_DEMO_MODE"] == "1"
    }

    /// Built-in script covering the constitution's three demo flows.
    static let builtinScript: [String: String] = [
        "meeting": "Here's your briefing: you have the investor sync at 10 and design review at 2. I've pulled your notes from last week's call and saved a one-page briefing to your notes — the open question is pricing.",
        "downloads": "Done — I organized your Downloads: invoices into Documents, screenshots into Pictures, and three installers into a Software folder. Nothing was deleted.",
        "pricing": "From your notes: the investor said pricing should be $29 one-time, not a subscription — he flagged that subscriptions would slow early adoption.",
        "calendar": "You have three events today: standup at 9, the investor sync at 10, and a design review at 2.",
        "joke": "I'd tell you a UDP joke, but you might not get it."
    ]

    static let fallbackLine = "In demo mode I only know my script — but everything you're seeing is the real engine."

    /// Deterministic reply: custom script (if provided) first, then built-ins,
    /// keys sorted so multiple matches always resolve the same way.
    static func reply(for prompt: String,
                      script: [String: String]? = nil) -> String {
        let table = script ?? activeScript
        let lower = prompt.lowercased()
        for key in table.keys.sorted() where lower.contains(key.lowercased()) {
            return table[key]!
        }
        return fallbackLine
    }

    /// Custom script from ARIA_DEMO_SCRIPT, else built-ins.
    static var activeScript: [String: String] {
        if let path = ProcessInfo.processInfo.environment["ARIA_DEMO_SCRIPT"],
           let custom = loadScript(from: path) {
            return custom
        }
        return builtinScript
    }

    static func loadScript(from path: String) -> [String: String]? {
        guard let data = FileManager.default.contents(atPath: (path as NSString).expandingTildeInPath) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }
}
