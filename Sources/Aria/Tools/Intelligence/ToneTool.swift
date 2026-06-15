import Foundation

/// Sets Aria's writing tone for drafts and emails.
struct SetToneTool: AriaTool {
    static let name = "set_tone"
    static let description = "Set Aria's writing tone for drafts and emails. Input: tone (auto/formal/casual/brief/friendly/professional)."
    static let paramHints: [String: String] = [
        "tone": "One of: auto, formal, casual, brief, friendly, professional"
    ]

    /// Allows injection of a non-shared ToneManager in tests.
    private let manager: ToneManager

    init(manager: ToneManager = .shared) {
        self.manager = manager
    }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let raw = input["tone"], let tone = WritingTone(rawValue: raw.lowercased()) else {
            let valid = WritingTone.allCases.map(\.rawValue).joined(separator: ", ")
            return .fail("Unknown tone. Valid options: \(valid).")
        }
        await manager.set(tone)
        if tone == .auto {
            return .ok("Writing tone reset to auto — Aria will adapt to context.")
        }
        return .ok("Writing tone set to '\(tone.rawValue)'. All drafts will now use this style.")
    }
}

/// Reports Aria's current writing tone.
struct ToneStatusTool: AriaTool {
    static let name = "tone_status"
    static let description = "Check Aria's current writing tone."

    /// Allows injection of a non-shared ToneManager in tests.
    private let manager: ToneManager

    init(manager: ToneManager = .shared) {
        self.manager = manager
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let tone = await manager.current
        if tone == .auto {
            return .ok("Tone: auto (Aria adapts to context)")
        }
        return .ok("Tone: \(tone.rawValue) \u{2014} \(tone.instruction)")
    }
}
