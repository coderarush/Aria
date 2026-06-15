import Foundation

/// A single UI step the operator WOULD run. Mirrors the (tool, input) shape the Pilot
/// loop already produces, kept local so the preview has no dependency on the autonomy/
/// sub-agent code.
struct UIStep: Equatable {
    let tool: String                 // ui_click, ui_type, ui_key, ui_scroll, open_app
    let input: [String: String]

    init(tool: String, input: [String: String]) {
        self.tool = tool
        self.input = input
    }
}

/// Dry-run preview for a risky multi-step UI run: turn a plan's UI steps into a
/// human-readable list of what Aria WOULD do, WITHOUT executing anything — so the user
/// can eyeball a destructive sequence ("Click 'Send'", "Type '…'") before approving it.
///
/// Pure and `static` — no AX, no clicks, fully unit-testable.
enum OperatorPreview {
    /// Human-readable lines describing each step. `app` (the frontmost app name) is woven
    /// in when known, e.g. "Click 'Send' in Mail".
    static func preview(_ steps: [UIStep], app: String? = nil) -> [String] {
        steps.compactMap { line(for: $0, app: app) }
    }

    /// One step → one line, or nil for an unknown/no-op tool (skipped from the preview).
    static func line(for step: UIStep, app: String? = nil) -> String? {
        let inApp = (app?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : " in \($0)"
        } ?? ""

        switch step.tool {
        case "ui_click":
            guard let label = nonEmpty(step.input["label"]) else { return nil }
            let role = nonEmpty(step.input["role"]).map { " (\($0.replacingOccurrences(of: "AX", with: "")))" } ?? ""
            return "Click ‘\(label)’\(role)\(inApp)"

        case "ui_type":
            guard let text = nonEmpty(step.input["text"]) else { return nil }
            return "Type ‘\(truncate(text))’\(inApp)"

        case "ui_key":
            guard let combo = nonEmpty(step.input["combo"]) else { return nil }
            return "Press \(combo)\(inApp)"

        case "ui_scroll":
            let dir = nonEmpty(step.input["direction"]) ?? "down"
            return "Scroll \(dir)\(inApp)"

        case "open_app":
            guard let name = nonEmpty(step.input["name"]) ?? nonEmpty(step.input["app"]) else {
                return "Open an app"
            }
            return "Open \(name)"

        default:
            return nil   // unknown tool — leave it out rather than describe it wrong
        }
    }

    // MARK: helpers

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Keep typed-text previews short and single-line so a long paste doesn't flood the UI.
    private static func truncate(_ s: String, _ n: Int = 60) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ")
        return flat.count <= n ? flat : String(flat.prefix(n)) + "…"
    }
}
