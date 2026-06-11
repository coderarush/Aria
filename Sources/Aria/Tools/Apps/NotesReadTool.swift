import Foundation

/// Read from Apple Notes (V10 integrations: Notes was write-only via
/// save_note). Lists recent note titles, or searches titles + bodies and
/// returns matching content. AppleScript-based — needs the same Automation
/// permission the existing Notes save path uses.
struct NotesReadTool: AriaTool {
    static let name = "notes_read"
    static let description = "Read the user's Apple Notes. Input: {query?} — with a query, returns matching notes' content; without, lists recent note titles. Use when the user asks what's in their notes."
    static let paramHints: [String: String] = [
        "query": "Text to find in note titles or bodies (optional)"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        let query = (input["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let script: String
        if query.isEmpty {
            script = """
            tell application "Notes"
                set out to ""
                set theNotes to notes of default account
                set maxN to 10
                if (count of theNotes) < maxN then set maxN to (count of theNotes)
                repeat with i from 1 to maxN
                    set out to out & "• " & (name of item i of theNotes) & linefeed
                end repeat
                return out
            end tell
            """
        } else {
            let q = asLiteral(query)
            script = """
            tell application "Notes"
                set out to ""
                set found to 0
                repeat with n in notes of default account
                    if found ≥ 3 then exit repeat
                    set theName to name of n
                    set theBody to plaintext of n
                    ignoring case
                        if (theName contains "\(q)") or (theBody contains "\(q)") then
                            set found to found + 1
                            if (count of theBody) > 600 then set theBody to text 1 thru 600 of theBody
                            set out to out & "── " & theName & " ──" & linefeed & theBody & linefeed
                        end if
                    end ignoring
                end repeat
                return out
            end tell
            """
        }
        let result = await AppleScriptTool.execute(script)
        guard result.success else {
            return .fail("I couldn't read Notes — Aria may need Automation access for Notes (System Settings → Privacy & Security → Automation).")
        }
        let out = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty || out == "(done)" {
            return .ok(query.isEmpty ? "No notes found." : "No notes match “\(query)”.")
        }
        return .ok(query.isEmpty ? "Recent notes:\n\(out)" : out)
    }
}
