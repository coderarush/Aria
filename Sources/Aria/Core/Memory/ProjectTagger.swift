import Foundation

/// Project Memory 2.0 (V11 P5): conservative project-name inference from task
/// phrasing. Only tags when the user clearly names a project ("continue my
/// Verdai work", "the Atlas project", "work on Aria") — a missed tag is far
/// cheaper than a wrong one, since untagged entries still show in time-based
/// recall.
enum ProjectTagger {

    /// Words that can land in the project slot of a pattern but never name one.
    private static let stopwords: Set<String> = [
        "own", "it", "this", "that", "the", "my", "me", "a", "an", "some",
        "current", "new", "old", "same", "last", "next", "her", "his", "their",
        "your", "our", "today", "tomorrow", "yesterday"
    ]

    /// Returns the inferred project name (display-capitalized) or nil.
    static func infer(from title: String) -> String? {
        let patterns = [
            #"(?:my|the)\s+(\S+)\s+(?:work|project)\b"#,  // "my Verdai work", "the Atlas project"
            #"\bwork(?:ing)?\s+on\s+(?:the\s+)?(\S+)"#,   // "work on Aria"
            #"\bcontinue\s+(?:with\s+)?([A-Z]\S*)"#       // "continue Verdai"
        ]
        for pattern in patterns {
            guard let match = title.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
                  let captured = capture(pattern: pattern, in: String(title[match])) else { continue }
            let cleaned = captured.trimmingCharacters(in: .punctuationCharacters)
            guard !cleaned.isEmpty, !stopwords.contains(cleaned.lowercased()) else { continue }
            return display(cleaned)
        }
        return nil
    }

    /// First capture group of `pattern` in `text`.
    private static func capture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// Capitalize the first letter for stable display/grouping ("verdai" → "Verdai")
    /// while preserving interior casing ("iOS" stays "iOS").
    private static func display(_ name: String) -> String {
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }
}
