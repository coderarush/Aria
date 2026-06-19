import Foundation

struct PendingFollowUp: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var subject: String
    var recipient: String
    var sentDate: Date
    var expectedReplyWithin: TimeInterval
    var snoozedUntil: Date?
    var resolved: Bool
}

actor FollowUpTracker {
    static let shared = FollowUpTracker()

    private let fileURL: URL
    private var followUps: [PendingFollowUp] = []

    init(fileURL: URL? = nil) {
        let url = fileURL ?? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("followups.json")
        self.fileURL = url
        self.followUps = Self.load(from: url)
    }

    func track(subject: String, recipient: String, expectedWithin: TimeInterval = 172800) async {
        let followUp = PendingFollowUp(
            id: UUID(),
            subject: subject,
            recipient: recipient,
            sentDate: Date(),
            expectedReplyWithin: expectedWithin,
            snoozedUntil: nil,
            resolved: false
        )
        followUps.append(followUp)
        save()
    }

    func overdue(now: Date = Date()) async -> [PendingFollowUp] {
        followUps.filter { item in
            guard !item.resolved else { return false }
            if let snoozed = item.snoozedUntil, now <= snoozed { return false }
            return now.timeIntervalSince(item.sentDate) > item.expectedReplyWithin
        }
    }

    func resolve(_ id: UUID) async {
        guard let idx = followUps.firstIndex(where: { $0.id == id }) else { return }
        followUps[idx].resolved = true
        save()
    }

    func snooze(_ id: UUID, for seconds: TimeInterval) async {
        guard let idx = followUps.firstIndex(where: { $0.id == id }) else { return }
        followUps[idx].snoozedUntil = Date().addingTimeInterval(seconds)
        save()
    }

    func all() async -> [PendingFollowUp] {
        followUps
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(followUps) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [PendingFollowUp] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([PendingFollowUp].self, from: data)) ?? []
    }
}
