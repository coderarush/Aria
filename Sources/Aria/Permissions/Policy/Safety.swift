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
                                                 "email_recent", "email_search", "email_draft",
                                                 // Connected-Google reads + the reversible-ish writes: a draft
                                                 // isn't sent and a calendar event can be deleted, so neither
                                                 // gates. (gmail_send is the external-comms one — it lives in
                                                 // importantTools below and stays gated.) Listed here so a
                                                 // draft body / event title containing a danger word ("send
                                                 // the report") can't trip the content gate.
                                                 "gmail_recent", "gcal_upcoming", "gmail_draft", "gcal_create",
                                                 // Connected-Drive reads + the reversible-ish file create (a
                                                 // created file can be trashed from Drive) don't gate, and
                                                 // drive_create is NOT in importantTools. Listed here so a file
                                                 // name / content containing a danger word ("send", "delete")
                                                 // can't trip the content gate.
                                                 "drive_search", "drive_read", "drive_create",
                                                 // Notion + Slack reads + the reversible-ish Notion page append
                                                 // (a block can be deleted) don't gate. (slack_send is external
                                                 // comms — it lives in importantTools below and stays gated.)
                                                 // Listed here so an appended note / search query containing a
                                                 // danger word ("post the update") can't trip the content gate.
                                                 "notion_search", "notion_append", "slack_recent"]
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

    /// Tools whose effect Aria can cleanly reverse (each records a ReversibleAction).
    static let reversibleTools: Set<String> = ["file_write", "clipboard", "save_note"]
    /// Extremely-important irreversible tools — the only class that gates approval
    /// under high autonomy (money, deletes with no undo, external comms, raw shell).
    static let importantTools: Set<String> = ["send_mail", "send_message", "send",
                                              "delete_file", "shell", "applescript",
                                              // Connected-Gmail send is external comms → gate it.
                                              "gmail_send",
                                              // Slack message send is external comms → gate it too.
                                              "slack_send"]

    /// Classify an action's consequence (v11.1.1 high-autonomy gate). Routine and
    /// reversible actions run free + receipted; only `.importantIrreversible` pauses.
    static func importance(tool: String, input: [String: String], summary: String) -> ActionImportance {
        if safeTools.contains(tool) { return .routine }
        if importantTools.contains(tool) || isDestructive(summary: summary) { return .importantIrreversible }
        if reversibleTools.contains(tool) { return .reversible }
        if isDestructive(tool: tool, input: input) { return .importantIrreversible }
        return .routine
    }
}
