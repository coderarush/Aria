import Foundation

/// Classifies a short spoken reply to a proactive offer as a yes or not-a-yes.
/// Deliberately conservative: anything that isn't clearly affirmative is treated
/// as a decline, so the user's words fall through to the normal command path.
enum ProactiveReply {
    static func isAffirmative(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }

        let negatives = ["not now", "no thanks", "nah", "stop", "don't", "do not", "cancel", "nope"]
        for n in negatives where t.contains(n) { return false }
        if t == "no" || t.hasPrefix("no ") { return false }

        let affirmatives = ["yes", "yeah", "yep", "yup", "sure", "okay", "ok", "do it",
                            "go ahead", "go for it", "please", "sounds good",
                            "definitely", "absolutely"]
        return affirmatives.contains { t.contains($0) }
    }
}
