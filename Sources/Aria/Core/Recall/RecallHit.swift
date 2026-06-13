import Foundation

/// One normalized result from the unified recall, regardless of which store it
/// came from. The four memory stores each speak a different dialect
/// (ConversationTurn, KnowledgeHit, MemoryFact, WorkEntry) and score on
/// incomparable scales; `RecallHit` is the common currency they all reduce to so
/// a single ranked list can span conversations, documents, context, and work.
struct RecallHit: Sendable, Codable, Equatable, Identifiable {
    /// Which store produced this hit. The raw value is the tag the tool prints
    /// (`[conversation]`, `[doc]`, `[context]`, `[work]`).
    enum Source: String, Sendable, Codable, CaseIterable {
        case conversation
        case document
        case context
        case work

        /// The bracketed tag shown to the model/user, e.g. "[doc]".
        var tag: String {
            switch self {
            case .conversation: return "[conversation]"
            case .document:     return "[doc]"
            case .context:      return "[context]"
            case .work:         return "[work]"
            }
        }
    }

    let source: Source
    let title: String
    let snippet: String
    let timestamp: Date?
    /// The source's own (un-normalized) relevance score, kept for transparency /
    /// debugging. The unified ranking does NOT compare these across sources — it
    /// fuses by rank (see `RecallRanker`).
    let score: Double

    /// Stable identity: source + title + snippet. Two hits from the same store
    /// describing the same thing collapse, which keeps the fused list clean.
    var id: String { "\(source.rawValue)|\(title)|\(snippet)" }

    init(source: Source, title: String, snippet: String,
         timestamp: Date? = nil, score: Double) {
        self.source = source
        self.title = title
        self.snippet = snippet
        self.timestamp = timestamp
        self.score = score
    }
}

/// The pure, synchronous heart of unified recall: given per-source ranked hit
/// lists, merge them into one ranked list with **Reciprocal Rank Fusion (RRF)**.
///
/// Why RRF rather than normalizing raw scores: the stores score on wholly
/// incomparable scales — substring presence (conversation), term-frequency +
/// title boost (documents), keyword-overlap + recency decay (context), substring
/// recency order (work). Min-maxing those against each other is meaningless. RRF
/// throws away the magnitudes and keeps only each source's *internal ordering*,
/// then fuses: a hit's fused score is the sum over the sources it appears in of
/// `1 / (k + rank)` (rank 0-based). This is order-preserving within a source,
/// rewards agreement across sources, and lets no single store dominate purely by
/// emitting large raw numbers. Deterministic: ties break by source order then id.
enum RecallRanker {
    /// RRF dampening constant. 60 is the value from the original Cormack et al.
    /// paper and the common default; large enough that top ranks don't swamp the
    /// tail, small enough that rank order still dominates.
    static let k = 60.0

    /// Fuse already-ranked per-source lists into one unified, ranked list.
    ///
    /// - Each inner array is ONE source's hits, already in that source's own
    ///   best-first order (index 0 = its top hit).
    /// - Empty inner arrays are skipped for free (they contribute nothing).
    /// - `limit` caps the returned list; `nil`/<=0 returns everything.
    /// - Ordering is fully deterministic.
    static func fuse(_ perSource: [[RecallHit]], limit: Int? = nil) -> [RecallHit] {
        // hit.id -> (the hit, accumulated RRF score). First occurrence wins the
        // representative hit; later duplicates only add to the score.
        var fused: [String: (hit: RecallHit, score: Double)] = [:]
        // Preserve a stable first-seen order so equal fused scores are
        // deterministic without depending on Dictionary iteration order.
        var order: [String] = []

        for hits in perSource {
            for (rank, hit) in hits.enumerated() {
                let contribution = 1.0 / (k + Double(rank))
                if let existing = fused[hit.id] {
                    fused[hit.id] = (existing.hit, existing.score + contribution)
                } else {
                    fused[hit.id] = (hit, contribution)
                    order.append(hit.id)
                }
            }
        }

        let firstSeenIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let ranked = order
            .map { fused[$0]! }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                // Tie-break 1: source declaration order (conversation < doc < …).
                let sa = sourceRank(a.hit.source), sb = sourceRank(b.hit.source)
                if sa != sb { return sa < sb }
                // Tie-break 2: stable first-seen order — fully deterministic.
                return firstSeenIndex[a.hit.id]! < firstSeenIndex[b.hit.id]!
            }
            .map { $0.hit }

        guard let limit, limit > 0 else { return ranked }
        return Array(ranked.prefix(limit))
    }

    private static func sourceRank(_ s: RecallHit.Source) -> Int {
        RecallHit.Source.allCases.firstIndex(of: s) ?? Int.max
    }
}
