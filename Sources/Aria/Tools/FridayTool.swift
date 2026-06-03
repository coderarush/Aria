import Foundation

/// A unit of capability Friday can invoke. Static tools (Shell, Mail, …) and the
/// dynamic tool factory both ultimately produce a `ToolResult`.
protocol FridayTool {
    /// Stable identifier the model references in `actions[].tool`.
    static var name: String { get }
    /// One line the model reads to decide when to use this tool.
    static var description: String { get }
    /// Whether running this needs explicit user confirmation (delete, send, …).
    var isDestructive: Bool { get }
    /// Execute with model-provided input.
    func run(input: [String: String]) async throws -> ToolResult
}

extension FridayTool {
    var isDestructive: Bool { false }
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
}

enum ToolError: Error, Equatable {
    case missingInput(String)
    case executionFailed(String)
    case timedOut
    case interpreterNotFound(String)
}
