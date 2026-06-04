import Foundation

/// Decides whether a step is destructive/irreversible and therefore needs a
/// confirm, even in fully-autonomous mode.
enum Safety {
    private static let dangerTools: Set<String> = ["send_mail", "send_message", "send", "delete_file"]
    private static let dangerWords = ["rm ", "rm -", "delete", "remove", "send", "email", "post",
                                      "overwrite", "drop ", "kill", "shutdown", "format", "purchase", "pay"]
    static func isDestructive(tool: String, input: [String: String]) -> Bool {
        if dangerTools.contains(tool) { return true }
        let blob = (tool + " " + input.values.joined(separator: " ")).lowercased()
        return dangerWords.contains { blob.contains($0) }
    }
}
