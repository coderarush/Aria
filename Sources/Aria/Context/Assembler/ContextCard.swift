import Foundation

/// Where a context card came from. Lets Aria (and the user) reason about the
/// kind of signal — "from your calendar" reads differently than "a file you
/// just downloaded".
enum ContextSource: String, Codable, Sendable {
    case file
    case calendar
    case mail
    case app
    case message
}

/// One lightweight slice of the user's world: a recent file, an upcoming event,
/// a mail subject. The Personal Context Engine aggregates these from cheap
/// Mac-wide signals so Aria knows what's going on around the user without
/// indexing their documents (that's the Knowledge Engine's job).
///
/// Retrieval is lexical (term frequency + title boost), mirroring
/// `KnowledgeIndex` — deterministic, fast, zero model dependency, and trivially
/// testable as a pure function over an in-memory card set.
struct ContextCard: Codable, Sendable, Equatable {
    let id: String
    let source: ContextSource
    let title: String
    let snippet: String
    let timestamp: Date

    // MARK: Relevance

    /// Pure lexical relevance of this card to a set of query terms. Higher is
    /// better; 0 means no overlap. Term frequency over title+snippet, with a
    /// title-match boost so a card whose title names the query ranks above one
    /// that only mentions it in the body.
    ///
    /// Same shape as `KnowledgeIndex.search`'s scoring so behavior is consistent
    /// across both engines.
    func relevance(to terms: [String]) -> Double {
        guard !terms.isEmpty else { return 0 }
        let titleTerms = ContextCard.terms(title)
        let body = (title + " " + snippet).lowercased()
        var score = 0.0
        for t in terms where body.contains(t) {
            score += 1.0
        }
        // Title boost: every query term that appears in the title counts double.
        let titleBoost = Double(terms.filter { t in
            titleTerms.contains(where: { $0.hasPrefix(t) || t.hasPrefix($0) })
        }.count) * 2.0
        return score + titleBoost
    }

    /// Lowercased terms, stopwords removed. Identical tokenization to
    /// `KnowledgeIndex.terms` so the two engines rank queries the same way.
    static func terms(_ text: String) -> [String] {
        let stop: Set<String> = ["the", "a", "an", "of", "to", "in", "on", "and", "or",
                                 "what", "did", "say", "about", "is", "are", "was", "my",
                                 "me", "for", "with", "do", "does", "how", "this", "that"]
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stop.contains($0) }
    }
}
