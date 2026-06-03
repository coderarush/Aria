import Foundation

/// On-device, append-only log of observations. Rolling 90-day window, pruned
/// automatically, never exceeds ~10MB. Stores command/app/file events only —
/// never file contents. Nothing here is ever sent off-device.
struct ObservationStore: Codable, Equatable {
    var commands: [CommandEvent] = []
    var apps: [AppEvent] = []
    var files: [FileEvent] = []
    /// When observation began — used for the 14-day "no automation" rule.
    var startedAt: Date = Date()
}

actor ObservationLog {
    private(set) var store: ObservationStore
    private let fileURL: URL
    private let retention: TimeInterval = 90 * 24 * 3600
    private let maxEvents = 20_000   // hard cap to bound disk size

    init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultURL()
        self.fileURL = url
        self.store = Self.load(from: url) ?? ObservationStore()
    }

    static func defaultURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aria", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("observations.json")
    }

    var startedAt: Date { store.startedAt }

    /// Days since observation began (for the 14-day gate).
    func observationDays(now: Date = Date()) -> Int {
        Int(now.timeIntervalSince(store.startedAt) / (24 * 3600))
    }

    func recordCommand(_ command: String, at date: Date = Date()) {
        store.commands.append(CommandEvent(command: command, timestamp: date))
        prune(); save()
    }

    func recordApp(_ event: AppEvent) {
        store.apps.append(event)
        prune(); save()
    }

    func recordFile(_ event: FileEvent) {
        store.files.append(event)
        prune(); save()
    }

    func clear() {
        store = ObservationStore()
        save()
    }

    // MARK: Pruning

    private func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-retention)
        store.commands.removeAll { $0.timestamp < cutoff }
        store.apps.removeAll { $0.timestamp < cutoff }
        store.files.removeAll { $0.timestamp < cutoff }
        // Bound total size: trim oldest commands first.
        let total = store.commands.count + store.apps.count + store.files.count
        if total > maxEvents {
            let overflow = total - maxEvents
            store.commands.removeFirst(min(overflow, store.commands.count))
        }
    }

    // MARK: Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(store) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> ObservationStore? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ObservationStore.self, from: data)
    }
}
