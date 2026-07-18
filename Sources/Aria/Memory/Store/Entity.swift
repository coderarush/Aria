import Foundation

/// What kind of thing an `Entity` is. Lets Aria reason differently about a
/// person ("draft Sara a note") than a project ("how's the launch going") or a
/// place. Stored as a stable string so the JSON survives enum growth.
enum EntityKind: String, Codable, Sendable, CaseIterable {
    case person
    case project
    case place
    case thing
}

/// One node in Aria's model of YOU — a person you mention ("Sara"), a project
/// you refer to ("the launch deck"), a place, or a thing. The Identity store
/// resolves casual references in your speech to the right entity so Aria's
/// drafts and actions name the people and projects you actually mean.
///
/// Resolution is lexical (term overlap over name + aliases + notes, with a
/// name/alias-match boost), mirroring `ContextCard.relevance` — deterministic,
/// fast, zero model dependency, and trivially testable as a pure function.
struct Entity: Codable, Sendable, Equatable, Identifiable {
    let id: String
    var name: String
    var kind: EntityKind
    var aliases: [String]
    var notes: String
    var lastSeen: Date

    init(id: String? = nil,
         name: String,
         kind: EntityKind,
         aliases: [String] = [],
         notes: String = "",
         lastSeen: Date = Date()) {
        self.id = id ?? Entity.canonicalID(for: name)
        self.name = name
        self.kind = kind
        self.aliases = aliases
        self.notes = notes
        self.lastSeen = lastSeen
    }

    /// A stable identity key derived from the name, so re-mentioning the same
    /// person upserts the existing node instead of forking a duplicate.
    static func canonicalID(for name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Relevance

    /// True when `query` plausibly refers to this entity — any positive lexical
    /// overlap. Cheap predicate for filtering before ranking.
    func matches(_ query: String) -> Bool {
        relevance(to: Entity.terms(query)) > 0
    }

    /// Pure lexical relevance of this entity to a set of query terms. Higher is
    /// better; 0 means no overlap. Term frequency over name + aliases + notes,
    /// with a strong name/alias boost so "Sara" resolves the person named
    /// "Sara Lin" above someone who merely mentions Sara in their notes.
    ///
    /// Same shape as `ContextCard.relevance` so behavior is consistent across
    /// the engines.
    func relevance(to terms: [String]) -> Double {
        guard !terms.isEmpty else { return 0 }
        let nameTerms = Entity.terms(name) + aliases.flatMap { Entity.terms($0) }
        let body = ([name] + aliases + [notes]).joined(separator: " ").lowercased()
        var score = 0.0
        for t in terms where body.contains(t) {
            score += 1.0
        }
        // Name/alias boost: every query term that hits the name or an alias
        // counts triple — a reference is far more likely the person/project it
        // names than one merely mentioned in passing in the notes.
        let nameBoost = Double(terms.filter { t in
            nameTerms.contains(where: { $0.hasPrefix(t) || t.hasPrefix($0) })
        }.count) * 3.0
        return score + nameBoost
    }

    /// Lowercased terms, stopwords removed. Same tokenization as
    /// `ContextCard.terms` so the engines rank references the same way.
    static func terms(_ text: String) -> [String] {
        let stop: Set<String> = ["the", "a", "an", "of", "to", "in", "on", "and", "or",
                                 "what", "did", "say", "about", "is", "are", "was", "my",
                                 "me", "for", "with", "do", "does", "how", "this", "that",
                                 "who", "whos", "tell", "know"]
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stop.contains($0) }
    }
}
