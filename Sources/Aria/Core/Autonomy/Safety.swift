import Foundation

/// Decides whether a step is destructive/irreversible and therefore needs a
/// confirm, even in fully-autonomous mode.
enum Safety {
    private static let dangerTools: Set<String> = ["send_mail", "send_message", "send", "delete_file"]
    /// Tools that never perform a destructive action, so their input text (which may
    /// happen to contain "delete", "send", etc. as content) must not trip the gate.
    private static let safeTools: Set<String> = ["ui_read", "ui_type", "ui_scroll",
                                                 "web_search", "web_fetch", "file_read",
                                                 // Reading/drafting email isn't destructive — don't let the
                                                 // "email" danger word trip on these tool names. (send_mail
                                                 // is in dangerTools, which is checked first, so it stays gated.)
                                                 "email_recent", "email_search", "email_draft"]
    private static let dangerWords = ["rm ", "rm -", "delete", "remove", "send", "email", "post",
                                      "submit", "overwrite", "drop ", "kill", "shutdown", "format",
                                      "purchase", "pay"]
    static func isDestructive(tool: String, input: [String: String]) -> Bool {
        if dangerTools.contains(tool) { return true }
        if safeTools.contains(tool) { return false }   // reads/searches/typing aren't destructive
        let blob = (tool + " " + input.values.joined(separator: " ")).lowercased()
        return dangerWords.contains { blob.contains($0) }
    }

    /// True if the step's natural-language summary describes a destructive act.
    /// Used for agent steps (Comet/Atlas), where the danger verb lives in the
    /// summary ("send the email to John") rather than in a tool name.
    static func isDestructive(summary: String) -> Bool {
        let blob = summary.lowercased()
        return dangerWords.contains { blob.contains($0) }
    }
}
