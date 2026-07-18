import Foundation

/// A lightweight, on-device fingerprint of HOW the user writes — so Aria's
/// drafts sound like them, not like a generic assistant. Captured from sample
/// text the user actually wrote (sent mail, notes, messages): average sentence
/// length, greeting/sign-off habits, emoji and contraction frequency, and a
/// rough formality score.
///
/// `analyze` is a pure, deterministic `static` function over the samples — no
/// model, no network, no filesystem — so it's directly unit-testable, and the
/// whole profile is small Codable signal that never leaves the machine.
/// `styleGuide()` renders it into a short natural-language instruction an LLM
/// draft prompt can prepend ("Keep it brief, casual, no sign-off, no emoji").
struct StyleProfile: Codable, Sendable, Equatable {
    /// Mean words per sentence across the samples. ~8 is terse; ~25 is formal.
    var avgSentenceLength: Double
    /// Fraction of samples that open with a greeting ("Hi", "Hey", "Dear", …).
    var greetingRate: Double
    /// Fraction of samples that close with a sign-off ("Thanks", "Best", …).
    var signOffRate: Double
    /// Emoji glyphs per 100 words. 0 means none.
    var emojiPer100Words: Double
    /// Fraction of "is/are/not/…" opportunities written as contractions
    /// ("it's", "don't"). High = casual voice.
    var contractionRate: Double
    /// 0 (very casual) … 1 (very formal). Derived signal, see `analyze`.
    var formality: Double
    /// How many samples this profile was built from. 0 = empty/default.
    var sampleCount: Int

    /// A neutral default for users who haven't shared writing samples — no
    /// strong opinions, so `styleGuide()` stays out of the way.
    static let neutral = StyleProfile(
        avgSentenceLength: 15, greetingRate: 0, signOffRate: 0,
        emojiPer100Words: 0, contractionRate: 0.5, formality: 0.5, sampleCount: 0)

    // MARK: Analysis (pure — testable)

    /// Build a profile from raw writing samples. Deterministic: the same inputs
    /// always produce the same profile. Empty input yields `.neutral`.
    static func analyze(_ samples: [String]) -> StyleProfile {
        let texts = samples
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !texts.isEmpty else { return .neutral }

        var totalWords = 0
        var totalSentences = 0
        var greetings = 0
        var signOffs = 0
        var emoji = 0
        var contractions = 0
        var contractionOpportunities = 0

        for text in texts {
            let words = wordTokens(text)
            totalWords += words.count

            let sentences = sentenceCount(text)
            totalSentences += sentences

            if opensWithGreeting(text) { greetings += 1 }
            if closesWithSignOff(text) { signOffs += 1 }

            emoji += emojiCount(text)

            let (used, opp) = contractionStats(words)
            contractions += used
            contractionOpportunities += opp
        }

        let n = Double(texts.count)
        let avgLen = totalSentences > 0
            ? Double(totalWords) / Double(totalSentences)
            : Double(totalWords)
        let emojiRate = totalWords > 0
            ? Double(emoji) / Double(totalWords) * 100.0
            : 0
        let contractionRate = contractionOpportunities > 0
            ? Double(contractions) / Double(contractionOpportunities)
            : 0.5

        // Formality: longer sentences and sign-offs push formal; contractions
        // and emoji push casual. Clamped to 0…1. Tuned so a terse, contraction-
        // heavy, emoji-using sample lands clearly casual and a sign-off,
        // no-contraction sample lands clearly formal — even when polite sign-off
        // fragments ("Best regards.") shorten the average sentence length.
        let lengthSignal = clamp((avgLen - 8.0) / 17.0)        // 8 words → 0, 25 → 1
        let signOffSignal = Double(signOffs) / n
        let formality = clamp(
            0.30 * lengthSignal
            + 0.35 * signOffSignal
            - 0.45 * contractionRate
            - 0.30 * min(1.0, emojiRate / 3.0)
            + 0.40)

        return StyleProfile(
            avgSentenceLength: round(avgLen * 10) / 10,
            greetingRate: Double(greetings) / n,
            signOffRate: Double(signOffs) / n,
            emojiPer100Words: round(emojiRate * 10) / 10,
            contractionRate: round(contractionRate * 100) / 100,
            formality: round(formality * 100) / 100,
            sampleCount: texts.count)
    }

    // MARK: Style guide

    /// A short natural-language instruction an LLM draft prompt can prepend so a
    /// generated message sounds like the user. Empty string for `.neutral` so it
    /// adds nothing when we have no signal.
    func styleGuide() -> String {
        guard sampleCount > 0 else { return "" }
        var parts: [String] = []

        // Length / brevity.
        if avgSentenceLength <= 11 {
            parts.append("keep sentences short and punchy")
        } else if avgSentenceLength >= 22 {
            parts.append("use full, complete sentences")
        } else {
            parts.append("keep it brief")
        }

        // Formality.
        if formality >= 0.6 {
            parts.append("write in a formal, professional tone")
        } else if formality <= 0.4 {
            parts.append("keep it casual and conversational")
        } else {
            parts.append("use a relaxed but polished tone")
        }

        // Contractions.
        parts.append(contractionRate >= 0.5
            ? "use contractions (it's, don't, I'll)"
            : "avoid contractions")

        // Greeting.
        if greetingRate >= 0.5 {
            parts.append("open with a short greeting")
        } else if greetingRate <= 0.15 {
            parts.append("skip the greeting")
        }

        // Sign-off.
        if signOffRate >= 0.5 {
            parts.append("close with a brief sign-off")
        } else if signOffRate <= 0.15 {
            parts.append("no sign-off")
        }

        // Emoji.
        parts.append(emojiPer100Words >= 0.5 ? "emoji are welcome" : "no emoji")

        let body = parts
            .enumerated()
            .map { $0.offset == 0 ? $0.element.prefix(1).uppercased() + $0.element.dropFirst() : $0.element }
            .joined(separator: ", ")
        return "Match the user's writing voice: \(body)."
    }

    // MARK: Tokenization helpers (pure)

    static func wordTokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: " \t\n\r"))
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'’"))) }
            .filter { !$0.isEmpty }
    }

    static func sentenceCount(_ text: String) -> Int {
        let parts = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return max(1, parts.count)
    }

    private static let greetingWords: Set<String> = [
        "hi", "hey", "hello", "dear", "greetings", "yo", "morning", "afternoon", "evening"
    ]
    private static let signOffWords: Set<String> = [
        "thanks", "thank", "best", "regards", "cheers", "sincerely", "warmly",
        "ttyl", "xoxo"
    ]

    static func opensWithGreeting(_ text: String) -> Bool {
        guard let first = firstWord(text) else { return false }
        return greetingWords.contains(first)
    }

    static func closesWithSignOff(_ text: String) -> Bool {
        // Sign-offs sit on their own line ("Thanks,\nArush") or close the message
        // inline ("…align on strategy. Best regards."). Check the first word of
        // the final non-empty line AND the last few words of the whole message so
        // both shapes are caught.
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let last = lines.last, let first = firstWord(last),
           signOffWords.contains(first) {
            return true
        }
        // Inline sign-off: scan the trailing window of words for a sign-off term.
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words.suffix(3).contains(where: { signOffWords.contains($0) })
    }

    private static func firstWord(_ text: String) -> String? {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first(where: { !$0.isEmpty })
    }

    static func emojiCount(_ text: String) -> Int {
        text.unicodeScalars.filter { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x238C }.count
    }

    /// (contractions used, opportunities) over the given word tokens. An
    /// opportunity is a contraction OR its expanded two-word form.
    static func contractionStats(_ words: [String]) -> (used: Int, opportunities: Int) {
        var used = 0
        var opportunities = 0
        var i = 0
        while i < words.count {
            let w = words[i].replacingOccurrences(of: "’", with: "'")
            if w.contains("'") && contractionForms.contains(w) {
                used += 1
                opportunities += 1
                i += 1
                continue
            }
            // Expanded two-word forms count as a "didn't contract" opportunity.
            if i + 1 < words.count, expandedFirsts.contains(w),
               expandedSeconds.contains(words[i + 1]) {
                opportunities += 1
                i += 2
                continue
            }
            i += 1
        }
        return (used, opportunities)
    }

    private static let contractionForms: Set<String> = [
        "it's", "i'm", "i'll", "i've", "don't", "doesn't", "didn't", "can't",
        "won't", "isn't", "aren't", "wasn't", "weren't", "we'll", "we're",
        "we've", "you're", "you'll", "you've", "they're", "they'll", "that's",
        "there's", "here's", "let's", "wouldn't", "couldn't", "shouldn't",
        "haven't", "hasn't", "hadn't", "what's", "who's"
    ]
    private static let expandedFirsts: Set<String> = [
        "it", "i", "do", "does", "did", "can", "will", "is", "are", "was",
        "were", "we", "you", "they", "that", "there", "here", "let", "would",
        "could", "should", "have", "has", "had", "what", "who", "cannot"
    ]
    private static let expandedSeconds: Set<String> = [
        "is", "am", "will", "have", "not", "are", "us", "would"
    ]

    private static func clamp(_ x: Double) -> Double { min(1.0, max(0.0, x)) }
}
