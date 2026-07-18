import Foundation

/// What to retrieve for (spec §31 inputs, distilled).
struct RetrievalQuery: Sendable {
    var objectiveID: UUID?
    var keywords: [String]
    var now: Date
    var limit: Int
}

/// Ranks memory records against the current situation (spec §31).
///
/// Relevance blends importance, objective match, recency, and keyword overlap.
/// Expired records are excluded. Pure and synchronous — fast enough for the
/// <50 ms budget since it operates on an in-memory slice.
struct ContextualRetrieval: Sendable {

    func retrieve(from records: [MemoryRecord], query: RetrievalQuery) -> [MemoryRecord] {
        records
            .filter { !$0.isExpired(asOf: query.now) }
            .map { ($0, relevance(of: $0, for: query)) }
            .sorted { $0.1 > $1.1 }
            .prefix(query.limit)
            .map(\.0)
    }

    private func relevance(of record: MemoryRecord, for query: RetrievalQuery) -> Double {
        var score = record.importance

        if let objective = query.objectiveID, record.objectiveID == objective {
            score += 1.0
        }

        // Recency: newer records score higher; decays over hours.
        let ageHours = max(0, query.now.timeIntervalSince(record.timestamp)) / 3_600
        score += 1.0 / (1.0 + ageHours)

        // Keyword overlap with the summary.
        let summary = record.summary.lowercased()
        let hits = query.keywords.filter { summary.contains($0.lowercased()) }.count
        score += Double(hits) * 0.5

        return score
    }
}
