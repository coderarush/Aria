import Foundation

/// Per-suggestion feedback accounting, keyed by `Suggestion.dedupeKey`.
struct SuggestionFeedback: Codable, Equatable {
    var accepts: Int = 0
    var dismisses: Int = 0
    var consecutiveDismisses: Int = 0
    var lastDismiss: Date?
}

/// Tracks how the user has responded to each recurring suggestion and decides
/// when to stop offering it. A suggestion is suppressed after
/// `suppressionThreshold` consecutive dismissals, and that suppression decays
/// after `decay` so a once-rejected suggestion can return if behaviour changes.
/// An `accepted` outcome resets the streak.
struct ProactiveStore: Codable, Equatable {

    static let suppressionThreshold = 3
    static let decay: TimeInterval = 14 * 24 * 3600   // 14 days

    private(set) var feedback: [String: SuggestionFeedback] = [:]

    mutating func record(_ outcome: SuggestionOutcome, key: String, now: Date) {
        var f = feedback[key] ?? SuggestionFeedback()
        switch outcome {
        case .accepted:
            f.accepts += 1
            f.consecutiveDismisses = 0
            f.lastDismiss = nil
        case .dismissed:
            f.dismisses += 1
            f.consecutiveDismisses += 1
            f.lastDismiss = now
        case .expired:
            break   // an ignored/expired suggestion is not a rejection
        }
        feedback[key] = f
    }

    func isSuppressed(key: String, now: Date) -> Bool {
        guard let f = feedback[key],
              f.consecutiveDismisses >= Self.suppressionThreshold,
              let last = f.lastDismiss else { return false }
        return now.timeIntervalSince(last) < Self.decay
    }
}

/// Disk persistence for `ProactiveStore`, kept separate so the model stays pure
/// and testable. Lives next to the other Application Support data.
enum ProactiveStoreFile {
    static func defaultURL() -> URL {
        PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("proactive.json")
    }

    static func load(from url: URL = defaultURL()) -> ProactiveStore {
        guard let data = try? Data(contentsOf: url) else { return ProactiveStore() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ProactiveStore.self, from: data)) ?? ProactiveStore()
    }

    static func save(_ store: ProactiveStore, to url: URL = defaultURL()) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(store) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
