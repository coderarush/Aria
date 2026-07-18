import Foundation
import AppKit

/// V11 P12 — politely quit an app (Focus Mode closes distractions with it).
/// Reversible by design: macOS apps save state, and reopening restores it.
/// Finder and Aria itself are protected; an app that isn't running succeeds
/// as a no-op.
struct QuitAppTool: AriaTool {
    static let name = "quit_app"
    static let description = "Quit a running application politely (it saves its state). Use to close distracting apps for focus, or when the user asks to close an app. Input: {name}."
    static let paramHints: [String: String] = ["name": "The application's name, e.g. Messages"]

    private static let protected: Set<String> = ["finder", "aria"]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let name = input["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            throw ToolError.missingInput("name")
        }
        guard !Self.protected.contains(name.lowercased()) else {
            return .fail("I won't quit \(name) — it's essential.")
        }
        let running = await MainActor.run {
            NSWorkspace.shared.runningApplications
                .contains { $0.localizedName?.lowercased() == name.lowercased() }
        }
        guard running else { return .ok("\(name) isn't running.") }
        let script = "tell application \(Self.quoted(name)) to quit"
        let result = await AppleScriptTool.execute(script)
        return result.success
            ? .ok("Closed \(name).")
            : .fail("I couldn't quit \(name) — it may be blocking on an unsaved document.")
    }

    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
