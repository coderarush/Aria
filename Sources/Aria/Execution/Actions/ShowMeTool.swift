import Foundation

/// "Show me where X is" / "point at the export button" — Aria draws a guidance
/// blob onto the located element instead of (or before) clicking it. This is the
/// teacher move: she points so YOU act, rather than taking over. Locates via the
/// same confidence-scored vision targeting as computer use; the marker auto-expires.
struct ShowMeTool: AriaTool {
    static let name = "show_me"
    static let description =
        "Point at or highlight something on the user's screen by pooling a marker blob onto it. Use when the user asks where something is, to show/point at a button or UI element, or to guide them through a step instead of doing it for them."
    static var paramHints: [String: String] {
        ["target": "what to point at on screen, e.g. 'the Export button' or 'the search field'"]
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let target = (input["target"] ?? input["query"] ?? input["element"] ?? "").trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { throw ToolError.missingInput("target") }

        guard let hit = await VisionLocator.locateScored(target) else {
            return .fail("I couldn't find \"\(target)\" on screen.")
        }
        let point = hit.point
        await MainActor.run {
            AriaStage.shared.point(at: point, label: target)
        }
        if hit.confidence < 0.45 {
            return .ok("I marked where I think \"\(target)\" is — not fully sure, look near the blob.")
        }
        return .ok("Pointing at \(target) — see the blob on screen.")
    }
}
