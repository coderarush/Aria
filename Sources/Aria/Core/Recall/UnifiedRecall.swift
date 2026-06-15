import Foundation

/// One recall to search everything Aria remembers. "What did I tell Sara about
/// pricing?" should hit past conversations, the user's own documents, durable
/// personal context, AND work history in a single pass — not four separate tools
/// the model has to remember to chain.
///
/// `UnifiedRecall` fans the query out to each available store **concurrently**
/// (async-let), reuses each store's existing lexical search read-only, normalizes
/// every hit into a `RecallHit`, and hands the per-source lists to the pure
/// `RecallRanker.fuse` (Reciprocal Rank Fusion) for one merged, ranked result.
///
/// Sources wired:
///  - `.conversation` → `ConversationMemory.search` (substring over turns)
///  - `.document`     → `KnowledgeIndex.search` (lexical; opt-in, privacy-gated)
///  - `.context`      → `LongTermMemory.recall` (durable personal facts/prefs —
///                       the cross-session "personal context" store)
///  - `.work`         → `WorkJournal.search` (task/agent history)
///
/// Each source degrades gracefully: empty or disabled stores simply contribute an
/// empty list, which the fuser skips. Knowledge is skipped entirely when the user
/// hasn't opted in (privacy-first), so we never even touch the index.
actor UnifiedRecall {
    private let conversation: ConversationMemory?
    private let knowledge: KnowledgeIndex?
    private let context: LongTermMemory?
    private let work: WorkJournal?

    /// How many hits to pull from each source before fusing. A per-source cap (not
    /// just a global one) is what keeps any single store from flooding the merge.
    private let perSourceLimit: Int

    /// `knowledgeEnabled` is captured at construction (read on the main actor by
    /// the caller) so the actor stays self-contained and testable without UI/UserDefaults.
    private let knowledgeEnabled: Bool

    private let ambient: PersonalContextEngine?
    private let entities: EntityStore?

    init(conversation: ConversationMemory? = nil,
         knowledge: KnowledgeIndex? = .shared,
         context: LongTermMemory? = .shared,
         work: WorkJournal? = .shared,
         ambient: PersonalContextEngine? = .shared,
         entities: EntityStore? = .shared,
         knowledgeEnabled: Bool = KnowledgeSettings.load().enabled,
         perSourceLimit: Int = 6) {
        self.conversation = conversation
        self.knowledge = knowledge
        self.context = context
        self.work = work
        self.ambient = ambient
        self.entities = entities
        self.knowledgeEnabled = knowledgeEnabled
        self.perSourceLimit = max(1, perSourceLimit)
    }

    /// Search everything, return the top `limit` unified hits, best-first.
    func recall(_ query: String, limit: Int = 8) async -> [RecallHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        // Fan out concurrently. Each branch is independent; nothing shared.
        async let convHits = conversationHits(q)
        async let docHits  = documentHits(q)
        async let ctxHits  = contextHits(q)
        async let workHits = workHits(q)
        async let ambHits  = ambientHits(q)
        async let entHits  = entityHits(q)

        // Order here defines the source tie-break order in the fuser.
        let perSource = await [convHits, docHits, ctxHits, workHits, ambHits, entHits]
        return RecallRanker.fuse(perSource, limit: limit)
    }

    /// People/projects the user has told Aria about (opt-in personalization), so a
    /// reference like "Sara" or "the launch deck" resolves to what Aria knows.
    private func entityHits(_ query: String) async -> [RecallHit] {
        guard let entities, await entities.isEnabled else { return [] }
        let found = await entities.search(query, limit: perSourceLimit)
        return found.enumerated().map { idx, e in
            RecallHit(source: .entity, title: e.name,
                      snippet: e.notes.isEmpty ? e.kind.rawValue : e.notes,
                      timestamp: nil, score: Double(perSourceLimit - idx))
        }
    }

    /// Ambient personal context — recent files, open apps, messages, calendar.
    /// Opt-in (skipped when disabled) and searches already-loaded cards (no
    /// refresh) so recall stays fast.
    private func ambientHits(_ query: String) async -> [RecallHit] {
        guard let ambient, await ambient.isEnabled else { return [] }
        let cards = await ambient.search(query, limit: perSourceLimit)
        return cards.enumerated().map { idx, card in
            RecallHit(source: .ambient, title: card.title, snippet: card.snippet,
                      timestamp: card.timestamp, score: Double(perSourceLimit - idx))
        }
    }

    // MARK: Per-source adapters (each normalizes into [RecallHit], best-first)

    private func conversationHits(_ query: String) async -> [RecallHit] {
        guard let conversation else { return [] }
        let turns = await conversation.search(query)
        // ConversationMemory.search returns oldest-first substring matches with no
        // score. Rank newest-first (most recent context is most useful) and assign
        // a descending positional score purely for transparency.
        let ordered = turns.sorted { $0.timestamp > $1.timestamp }.prefix(perSourceLimit)
        return ordered.enumerated().map { idx, turn in
            // Prefer what the user said as the title; fall back to Aria's reply.
            let title = Self.firstLine(turn.transcript.isEmpty ? turn.responseMessage : turn.transcript)
            let snippet = Self.snippet(turn.responseMessage.isEmpty ? turn.transcript : turn.responseMessage)
            return RecallHit(source: .conversation, title: title, snippet: snippet,
                             timestamp: turn.timestamp,
                             score: Double(perSourceLimit - idx))
        }
    }

    private func documentHits(_ query: String) async -> [RecallHit] {
        // Privacy gate: never touch the index unless the user opted in.
        guard knowledgeEnabled, let knowledge else { return [] }
        let hits = await knowledge.search(query, limit: perSourceLimit)
        return hits.map { h in
            RecallHit(source: .document, title: h.title, snippet: Self.snippet(h.snippet),
                      timestamp: nil, score: h.score)
        }
    }

    private func contextHits(_ query: String) async -> [RecallHit] {
        guard let context else { return [] }
        let facts = await context.recall(for: query, limit: perSourceLimit)
        return facts.map { f in
            RecallHit(source: .context, title: f.kind.capitalized,
                      snippet: Self.snippet(f.text), timestamp: f.createdAt,
                      // recall() is already relevance-ordered; the score field is
                      // informational only (the fuser uses rank, not magnitude).
                      score: 1.0)
        }
    }

    private func workHits(_ query: String) async -> [RecallHit] {
        guard let work else { return [] }
        let entries = await work.search(query, limit: perSourceLimit)
        return entries.map { e in
            let mark = e.ok ? "✓" : "✗"
            let snippet = e.outcome.isEmpty ? "\(mark) (no outcome recorded)" : "\(mark) \(e.outcome)"
            return RecallHit(source: .work, title: e.title, snippet: Self.snippet(snippet),
                             timestamp: e.date, score: 1.0)
        }
    }

    // MARK: Formatting helpers

    private static func firstLine(_ s: String) -> String {
        let line = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
        return snippet(line.trimmingCharacters(in: .whitespaces), max: 80)
    }

    private static func snippet(_ s: String, max: Int = 200) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flat.count > max else { return flat }
        return String(flat.prefix(max)) + "…"
    }
}
