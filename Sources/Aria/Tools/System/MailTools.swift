import Foundation

/// Email via Apple Mail (AppleScript). Native-macOS integration — works with whatever
/// accounts are configured in Mail, INCLUDING Gmail, with no OAuth client to set up.
/// Per the directive's integration order (official API → native macOS → UI automation),
/// this is the reliable, zero-setup path for a pre-release; a first-party Gmail API
/// client can layer in later behind the same tool names.
///
/// Reading/searching give Aria email *context* (the P3 gap). Drafting *prepares* a
/// visible message but never sends. Sending goes through `send_mail`, which is gated
/// for confirmation at the execution chokepoint (Safety lists it as destructive).
/// Escape a string for an AppleScript double-quoted literal. Critically, AppleScript
/// source can't contain raw newlines/tabs inside a string — a multi-line email body
/// would break the script — so those become \n \r \t escapes too (backslashes first).
func asLiteral(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: "\"", with: "\\\"")
     .replacingOccurrences(of: "\n", with: "\\n")
     .replacingOccurrences(of: "\r", with: "\\r")
     .replacingOccurrences(of: "\t", with: "\\t")
}

/// Read the most recent inbox messages (sender, subject, date).
struct EmailRecentTool: AriaTool {
    static let name = "email_recent"
    static let description = "Read the user's most recent inbox emails (sender, subject, date) from Apple Mail. Use for 'check my email', 'what's in my inbox', 'any new mail'. Input: {count?}."
    static let paramHints: [String: String] = ["count": "How many recent messages (default 10)"]

    func run(input: [String: String]) async throws -> ToolResult {
        let count = max(1, min(Int(input["count"] ?? "10") ?? 10, 40))
        let script = """
        tell application "Mail"
            set out to ""
            set theMessages to messages of inbox
            set n to count of theMessages
            set lim to \(count)
            if n < lim then set lim to n
            repeat with i from 1 to lim
                set m to item i of theMessages
                set out to out & (sender of m) & " | " & (subject of m) & " | " & (date received of m as string) & linefeed
            end repeat
            return out
        end tell
        """
        let r = await AppleScriptTool.execute(script)
        guard r.success else {
            return .fail("I couldn't read Mail — Aria may need Automation access for Mail (System Settings → Privacy & Security → Automation), and Mail must have an account set up.")
        }
        let rows = r.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return rows.isEmpty ? .ok("Your inbox looks empty.")
                            : .ok("Recent email (\(rows.count)):\n" + rows.joined(separator: "\n"))
    }
}

/// Search the inbox by sender or subject.
struct EmailSearchTool: AriaTool {
    static let name = "email_search"
    static let description = "Search Apple Mail's inbox by sender or subject text. Use for 'find the email from Sarah', 'the invoice email'. Input: {query}."
    static let paramHints: [String: String] = ["query": "Text to match in sender or subject"]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let query = input["query"], !query.isEmpty else { throw ToolError.missingInput("query") }
        let q = asLiteral(query)
        // Subject/sender only (fast) — body filtering loads every message and is slow.
        let script = """
        tell application "Mail"
            set out to ""
            set hits to (messages of inbox whose subject contains "\(q)")
            set n to count of hits
            set lim to 15
            if n < lim then set lim to n
            repeat with i from 1 to lim
                set m to item i of hits
                set out to out & (sender of m) & " | " & (subject of m) & " | " & (date received of m as string) & linefeed
            end repeat
            return out
        end tell
        """
        let r = await AppleScriptTool.execute(script)
        guard r.success else {
            return .fail("I couldn't search Mail — Aria may need Automation access for Mail (System Settings → Privacy & Security → Automation).")
        }
        let rows = r.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return rows.isEmpty ? .ok("No inbox emails matched “\(query)”.")
                            : .ok("Matches for “\(query)” (\(rows.count)):\n" + rows.joined(separator: "\n"))
    }
}

/// Prepare a visible draft in Mail — never sends.
struct EmailDraftTool: AriaTool {
    static let name = "email_draft"
    static let description = "Prepare (but do NOT send) an email draft in Apple Mail, opened for the user to review. Use for 'draft an email to…', 'start a reply'. Input: {to?, subject?, body}."
    static let paramHints: [String: String] = [
        "to": "Recipient address (optional)",
        "subject": "Subject line (optional)",
        "body": "Message body"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        let toRaw = input["to"] ?? ""
        let to = asLiteral(toRaw)
        let subject = asLiteral(input["subject"] ?? "")
        let body = asLiteral(input["body"] ?? input["content"] ?? "")
        let recipientLine = to.isEmpty ? "" :
            "tell m to make new to recipient at end of to recipients with properties {address:\"\(to)\"}"
        let script = """
        tell application "Mail"
            set m to make new outgoing message with properties {subject:"\(subject)", content:"\(body)", visible:true}
            \(recipientLine)
            activate
        end tell
        return "ok"
        """
        let r = await AppleScriptTool.execute(script)
        return r.success
            ? .ok("Drafted the email in Mail\(toRaw.isEmpty ? "" : " to \(toRaw)") — review and send when you're ready.")
            : .fail("I couldn't open a draft in Mail — Aria may need Automation access for Mail.")
    }
}

/// Send an email. DESTRUCTIVE — gated for confirmation at the execution chokepoint.
struct SendMailTool: AriaTool {
    static let name = "send_mail"
    static let description = "Send an email via Apple Mail. Aria confirms before sending. Input: {to, subject?, body}."
    static let paramHints: [String: String] = [
        "to": "Recipient address",
        "subject": "Subject line (optional)",
        "body": "Message body"
    ]
    var isDestructive: Bool { true }   // also caught by Safety; explicit for defense in depth

    func run(input: [String: String]) async throws -> ToolResult {
        guard let toRaw = input["to"], !toRaw.isEmpty else { throw ToolError.missingInput("to") }
        let to = asLiteral(toRaw)
        let subject = asLiteral(input["subject"] ?? "")
        let body = asLiteral(input["body"] ?? input["content"] ?? "")
        let script = """
        tell application "Mail"
            set m to make new outgoing message with properties {subject:"\(subject)", content:"\(body)", visible:false}
            tell m to make new to recipient at end of to recipients with properties {address:"\(to)"}
            send m
        end tell
        return "sent"
        """
        let r = await AppleScriptTool.execute(script)
        return r.success
            ? .ok("Sent the email to \(toRaw).")
            : .fail("I couldn't send the email — Aria may need Automation access for Mail, and the account must be able to send.")
    }
}
