import Foundation
import AppKit

/// Run a bash command and capture output. 30s timeout.
struct ShellTool: AriaTool {
    static let name = "shell"
    static let description = "Run a bash command. Input: {command}. Returns stdout/stderr."
    static let paramHints: [String: String] = ["command": "The bash command to run"]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let command = input["command"], !command.isEmpty else {
            throw ToolError.missingInput("command")
        }
        let out = try await ScriptRunner().run(code: command, language: .bash, timeout: 30)
        return out.success
            ? .ok(out.stdout.isEmpty ? "(done)" : out.stdout, diagnostics: out.stderr.isEmpty ? nil : out.stderr)
            : .fail("exit \(out.exitCode)", diagnostics: out.stderr.isEmpty ? out.stdout : out.stderr)
    }
}

/// Execute AppleScript and return its result.
struct AppleScriptTool: AriaTool {
    static let name = "applescript"
    static let description = "Run AppleScript to control Mac apps. Input: {script}."
    static let paramHints: [String: String] = ["script": "The AppleScript source to execute"]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let script = input["script"], !script.isEmpty else {
            throw ToolError.missingInput("script")
        }
        return await Self.execute(script)
    }

    /// Run on the main thread (NSAppleScript requirement).
    @MainActor
    static func execute(_ script: String) -> ToolResult {
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            return .fail("AppleScript error: \(error[NSAppleScript.errorMessage] ?? "unknown")")
        }
        return .ok(result?.stringValue ?? "(done)")
    }
}

/// Create or overwrite a file. Destructive (overwrite).
struct FileWriteTool: AriaTool {
    static let name = "file_write"
    static let description = "Write text to a file (creates/overwrites). Input: {path, content}."
    static let paramHints: [String: String] = [
        "path": "Absolute or tilde-expanded path to the file",
        "content": "Text content to write"
    ]
    var isDestructive: Bool { true }

    func run(input: [String: String]) async throws -> ToolResult {
        guard let path = input["path"], !path.isEmpty else { throw ToolError.missingInput("path") }
        let content = input["content"] ?? ""
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return .ok("Wrote \(content.utf8.count) bytes to \(url.path)")
        } catch {
            return .fail("Write failed: \(error.localizedDescription)")
        }
    }
}

/// Read a file's contents.
struct FileReadTool: AriaTool {
    static let name = "file_read"
    static let description = "Read a text file. Input: {path}. Returns contents."
    static let paramHints: [String: String] = ["path": "Absolute or tilde-expanded path to the file"]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let path = input["path"], !path.isEmpty else { throw ToolError.missingInput("path") }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            return .ok(text)
        } catch {
            return .fail("Read failed: \(error.localizedDescription)")
        }
    }
}

/// Read or write the system clipboard.
struct ClipboardTool: AriaTool {
    static let name = "clipboard"
    static let description = "Read or write the clipboard. Input: {action: read|write, text?}."
    static let paramHints: [String: String] = [
        "action": "read or write",
        "text": "Text to copy (required when action is write)"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        let action = input["action"] ?? "read"
        return await MainActor.run {
            let pb = NSPasteboard.general
            if action == "write" {
                let text = input["text"] ?? ""
                pb.clearContents()
                pb.setString(text, forType: .string)
                return .ok("Copied to clipboard.")
            } else {
                return .ok(pb.string(forType: .string) ?? "(clipboard empty)")
            }
        }
    }
}

/// Post a macOS notification (via osascript, no entitlement needed).
struct NotificationTool: AriaTool {
    static let name = "notify"
    static let description = "Show a macOS notification. Input: {title, message}."
    static let paramHints: [String: String] = [
        "title": "Notification title",
        "message": "Notification body text"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        let title = (input["title"] ?? "Aria").replacingOccurrences(of: "\"", with: "'")
        let message = (input["message"] ?? "").replacingOccurrences(of: "\"", with: "'")
        let script = "display notification \"\(message)\" with title \"\(title)\""
        return await AppleScriptTool.execute(script)
    }
}
