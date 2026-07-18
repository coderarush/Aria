import Foundation

/// A timestamped routing decision as stored on disk.
struct RoutingLogEntry: Codable, Equatable, Sendable {
    let date: Date
    let decision: RoutingDecision
}

/// Durable ring buffer of routing decisions. This is the data source for the
/// Model Router Dashboard (Phase C): which model handled what, and why —
/// transparency over black-box behavior.
actor RoutingLog {
    static let shared = RoutingLog()

    private let fileURL: URL
    private let cap: Int
    private var entries: [RoutingLogEntry]

    init(fileURL: URL? = nil, cap: Int = 200) {
        let url = fileURL ?? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("routing.json")
        self.fileURL = url
        self.cap = cap
        self.entries = Self.load(from: url)
    }

    func record(_ decision: RoutingDecision, at date: Date = Date()) {
        entries.append(RoutingLogEntry(date: date, decision: decision))
        if entries.count > cap { entries.removeFirst(entries.count - cap) }
        save()
    }

    /// Newest first.
    func recent(_ limit: Int) -> [RoutingLogEntry] {
        Array(entries.suffix(limit).reversed())
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [RoutingLogEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RoutingLogEntry].self, from: data)) ?? []
    }
}
