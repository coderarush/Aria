import Foundation

/// A unit of capability Aria can invoke. Static tools (Shell, Mail, …) and the
/// dynamic tool factory both ultimately produce a `ToolResult`.
protocol AriaTool {
    /// Stable identifier the model references in `actions[].tool`.
    static var name: String { get }
    /// One line the model reads to decide when to use this tool.
    static var description: String { get }
    /// Whether running this needs explicit user confirmation (delete, send, …).
    var isDestructive: Bool { get }
    /// Parameter hints keyed by input key, for building Gemini functionDeclarations.
    /// Default: empty (tool takes no structured inputs).
    static var paramHints: [String: String] { get }
    /// Execute with model-provided input.
    func run(input: [String: String]) async throws -> ToolResult
}

extension AriaTool {
    var isDestructive: Bool { false }
    static var paramHints: [String: String] { [:] }
}

/// Outcome of a tool run. `output` is surfaced to the user / fed to the next step.
struct ToolResult: Equatable {
    let success: Bool
    let output: String
    /// Non-fatal diagnostics (e.g. stderr) kept separate from `output`.
    let diagnostics: String?

    init(success: Bool, output: String, diagnostics: String? = nil) {
        self.success = success
        self.output = output
        self.diagnostics = diagnostics
    }

    static func ok(_ output: String, diagnostics: String? = nil) -> ToolResult {
        ToolResult(success: true, output: output, diagnostics: diagnostics)
    }
    static func fail(_ output: String, diagnostics: String? = nil) -> ToolResult {
        ToolResult(success: false, output: output, diagnostics: diagnostics)
    }

    /// Canonical message for a user who declined a destructive-action confirmation.
    /// Centralized so the safety gate (producer) and the autonomy loop (consumer)
    /// agree on the marker without a new stored field (keeps `Equatable` intact).
    static let notApprovedMessage = "Cancelled — not approved."

    /// A failure produced because the user declined the confirmation gate.
    static func cancelled() -> ToolResult { .fail(notApprovedMessage) }

    /// True when this failure is a user decline. The autonomy loop uses this to
    /// avoid retrying or "recovering" something the user just said no to — which
    /// would otherwise re-prompt them for the same action.
    var wasDeclined: Bool { !success && output == ToolResult.notApprovedMessage }
}

enum ToolError: Error, Equatable {
    case missingInput(String)
    case executionFailed(String)
    case timedOut
    case interpreterNotFound(String)
}
