import Foundation

/// V11 P13 — "a new PDF just landed in Downloads; want a summary?"
/// Pure over an injected file lister; the production lister reads ~/Downloads
/// with FileManager. Only documents added in the last `freshWindow` seconds
/// count, so a launch never replays old files.
struct DownloadsSignalProvider: SignalProvider {
    struct NewFile: Sendable, Equatable {
        let name: String
        let addedAt: Date
    }

    let source: SuggestionSource = .downloads

    /// Files currently in Downloads with their added dates.
    private let recentFiles: @Sendable (Date) async -> [NewFile]
    private let freshWindow: TimeInterval

    /// Document types worth offering to summarize.
    private static let documentExtensions: Set<String> = ["pdf"]

    init(freshWindow: TimeInterval = 600,
         recentFiles: @escaping @Sendable (Date) async -> [NewFile] = DownloadsSignalProvider.scanDownloads) {
        self.freshWindow = freshWindow
        self.recentFiles = recentFiles
    }

    func candidates(now: Date) async -> [Suggestion] {
        let files = await recentFiles(now)
        return files.filter { file in
            now.timeIntervalSince(file.addedAt) < freshWindow
                && Self.documentExtensions.contains((file.name as NSString).pathExtension.lowercased())
        }.prefix(1).map { file in
            Suggestion(source: .downloads,
                       spokenLine: "A new PDF just landed — \(displayName(file.name)). Want a summary?",
                       action: .runCommand("Summarize the PDF named \(file.name) in my Downloads folder"),
                       confidence: 0.7,
                       urgency: .ambient,
                       createdAt: now,
                       expiry: now.addingTimeInterval(900),
                       dedupeKey: "downloads.pdf.\(file.name)")
        }
    }

    private func displayName(_ name: String) -> String {
        (name as NSString).deletingPathExtension
    }

    /// Production lister: ~/Downloads contents by .addedToDirectoryDate.
    @Sendable static func scanDownloads(now: Date) async -> [NewFile] {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.addedToDirectoryDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { url in
            guard let added = (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?
                .addedToDirectoryDate else { return nil }
            return NewFile(name: url.lastPathComponent, addedAt: added)
        }
    }
}

/// V11 P13 — "busy afternoon; want a recap?" Fires once the user has completed
/// `threshold`+ tasks today. One offer per day (stable dedupe key) — the
/// engine's suppression bookkeeping prevents repeats after dismissal.
struct SessionSignalProvider: SignalProvider {
    let source: SuggestionSource = .session

    /// Completed (ok) journal entries since start of day.
    private let completedTasks: @Sendable (Date) async -> Int
    private let threshold: Int

    init(threshold: Int = 4,
         completedTasks: @escaping @Sendable (Date) async -> Int = SessionSignalProvider.todaysCompletedTasks) {
        self.threshold = threshold
        self.completedTasks = completedTasks
    }

    func candidates(now: Date) async -> [Suggestion] {
        let count = await completedTasks(now)
        guard count >= threshold else { return [] }
        let day = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        return [Suggestion(source: .session,
                           spokenLine: "Productive day — \(count) things done so far. Want a quick recap?",
                           action: .runCommand("Show my timeline for today"),
                           confidence: 0.55,
                           urgency: .ambient,
                           createdAt: now,
                           expiry: now.addingTimeInterval(3600),
                           dedupeKey: "session.recap.\(Int(day))")]
    }

    @Sendable static func todaysCompletedTasks(now: Date) async -> Int {
        let start = Calendar.current.startOfDay(for: now)
        return await WorkJournal.shared.entries(from: start, to: now).filter(\.ok).count
    }
}
