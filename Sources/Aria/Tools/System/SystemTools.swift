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

/// Save text where the user can read it later. Tries Apple Notes first; if that
/// fails for any reason, falls back to a Markdown file on the Desktop AND the
/// clipboard AND a notification — so "write it down and give it to me" NEVER
/// dead-ends. Always succeeds and reports where the text landed.
struct SaveNoteTool: AriaTool {
    static let name = "save_note"
    static let description = "Save text so the user can read it later (Apple Notes, falling back to a Desktop file + clipboard). Input: {title?, content}. Use this for 'note', 'save', 'write it down', 'jot', 'remember this'."
    static let paramHints: [String: String] = [
        "title": "Short title / first line (optional)",
        "content": "The text to save"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        let content = (input["content"] ?? input["text"] ?? input["body"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw ToolError.missingInput("content") }
        let title = (input["title"]?.isEmpty == false ? input["title"]! : Self.firstLineTitle(content))

        // 1) Try Apple Notes (the user asked for "a note"). Notes derives the title
        //    from the first line of the HTML body, so we make that a bold heading.
        //    No hard-coded account/folder → uses the default account so it works on
        //    any setup (iCloud or "On My Mac").
        let escapedTitle = Self.htmlEscape(title)
        let escapedBody = Self.htmlEscape(content).replacingOccurrences(of: "\n", with: "<br>")
        let notesScript = """
        tell application "Notes" to make new note with properties {body:"<div><b>\(escapedTitle)</b></div><div>\(escapedBody)</div>"}
        """
        let notes = await AppleScriptTool.execute(notesScript)
        if notes.success {
            Log.trace("save_note: created Apple Note “\(title)”")
            // Also mirror to clipboard so it's instantly pasteable.
            await Self.copyToClipboard(content)
            return .ok("Saved a note titled “\(title)” in Apple Notes (and copied it to your clipboard).")
        }
        Log.trace("save_note: Notes failed (\(notes.output)); falling back to a Desktop file")

        // 2) Fallback: write a Markdown file to ~/Desktop/Aria Notes/, open it so the
        //    user can't miss it, copy to clipboard, and notify.
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/Aria Notes")
        let fileURL = dir.appendingPathComponent("\(Self.slug(title)).md")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let doc = "# \(title)\n\n\(content)\n"
            try doc.write(to: fileURL, atomically: true, encoding: .utf8)
            await Self.copyToClipboard(content)
            await MainActor.run { _ = NSWorkspace.shared.open(fileURL) }   // surface it immediately
            _ = await AppleScriptTool.execute(
                "display notification \"Saved “\(Self.asLiteral(title))” to your Desktop\" with title \"Aria\"")
            Log.trace("save_note: wrote + opened \(fileURL.path)")
            return .ok("Couldn't reach Apple Notes, so I saved it to your Desktop (Aria Notes/\(fileURL.lastPathComponent)), opened it, and copied it to your clipboard.")
        } catch {
            // 3) Last resort: clipboard only — still give it to the user.
            await Self.copyToClipboard(content)
            return .ok("I couldn't open Notes or write a file, so I've copied the text to your clipboard for you.")
        }
    }

    private static func firstLineTitle(_ s: String) -> String {
        let first = s.split(separator: "\n").first.map(String.init) ?? s
        let trimmed = first.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(60)).isEmpty ? "Aria Note" : String(trimmed.prefix(60))
    }
    private static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
    private static func asLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    private static func slug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = String(s.unicodeScalars.filter { allowed.contains($0) }).trimmingCharacters(in: .whitespaces)
        let dashed = cleaned.replacingOccurrences(of: " ", with: "-")
        return dashed.isEmpty ? "aria-note" : String(dashed.prefix(50))
    }
    @MainActor private static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
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
