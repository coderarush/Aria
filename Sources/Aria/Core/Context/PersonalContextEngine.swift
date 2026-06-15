import Foundation
import EventKit
import AppKit

/// "Aria knows your world." The Personal Context Engine aggregates lightweight,
/// Mac-wide signals into a small set of `ContextCard`s — recent files in
/// ~/Downloads and ~/Desktop, upcoming calendar events — so Aria can ground
/// answers in what's actually going on around the user. This is the
/// Siri-killer differentiator: ambient awareness without indexing documents.
///
/// Privacy-first and strictly opt-in: gated by the `app.personalContextEnabled`
/// UserDefaults key (default false). Everything stays on disk locally; nothing
/// leaves the machine. EventKit is read only when access is already granted —
/// the engine never prompts and skips gracefully when permission is missing.
///
/// Retrieval is lexical (see `ContextCard.relevance`), so `search` is a pure,
/// synchronous function over the loaded cards: deterministic and testable
/// without touching the filesystem or EventKit.
actor PersonalContextEngine {
    static let shared = PersonalContextEngine()

    /// UserDefaults key for the opt-in master switch. Read directly from
    /// UserDefaults (not AppSettings) so this subsystem stays self-contained.
    static let enabledKey = "app.personalContextEnabled"

    private let storeURL: URL
    private let defaults: UserDefaults
    private var cards: [ContextCard]

    init(storeURL: URL? = nil, defaults: UserDefaults = .standard) {
        let url = storeURL ?? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("personal-context.json")
        self.storeURL = url
        self.defaults = defaults
        self.cards = Self.load(from: url)
    }

    /// Whether the user has opted in. Default false.
    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    var cardCount: Int { cards.count }

    // MARK: Refresh

    /// Rebuild the card set from current signals and persist it. A no-op (and a
    /// privacy guard) when the engine is disabled: it clears any stored cards so
    /// nothing lingers on disk after the user opts out.
    func refresh() async {
        guard isEnabled else {
            if !cards.isEmpty { cards = []; save() }
            return
        }
        var built: [ContextCard] = []
        built.append(contentsOf: Self.recentFileCards(in: "~/Downloads", limit: 30))
        built.append(contentsOf: Self.recentFileCards(in: "~/Desktop", limit: 30))
        built.append(contentsOf: Self.upcomingEventCards(daysAhead: 7))
        // v2 signals. Apps are read on the main actor (NSWorkspace). Messages runs
        // off the actor with a hard timeout so a slow/locked DB never stalls us.
        built.append(contentsOf: await MainActor.run { Self.appCards(limit: 12) })
        built.append(contentsOf: await Task.detached { Self.messageCards(limit: 15) }.value)
        // Mail still deferred — Apple Mail needs an automation-permission prompt we
        // won't trigger silently; revisit once connectors land a Gmail path.
        cards = built
        save()
    }

    // MARK: Search (pure)

    /// Lexical ranking over the loaded cards. Synchronous and pure given the
    /// card set, so it's directly unit-testable. Empty query or empty corpus
    /// returns [].
    func search(_ query: String, limit: Int = 8) -> [ContextCard] {
        Self.rank(query, in: cards, limit: limit)
    }

    /// The ranking core, factored out as a `static` pure function so tests can
    /// exercise it against in-memory cards without constructing the actor.
    static func rank(_ query: String, in cards: [ContextCard], limit: Int = 8) -> [ContextCard] {
        let terms = ContextCard.terms(query)
        guard !terms.isEmpty, !cards.isEmpty else { return [] }
        let scored = cards
            .map { (card: $0, score: $0.relevance(to: terms)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
        return Array(scored.prefix(max(0, limit)).map { $0.card })
    }

    // MARK: Signal sources

    /// Recent files in a folder, newest first, as cards. Filename is the title;
    /// the full path is the snippet so Aria can act on it. Hidden files skipped.
    private static func recentFileCards(in folder: String, limit: Int) -> [ContextCard] {
        let root = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        let files = entries.compactMap { url -> (URL, Date)? in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { return nil }
            return (url, values?.contentModificationDate ?? .distantPast)
        }
        return files
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { url, mtime in
                ContextCard(id: "file:\(url.path)",
                            source: .file,
                            title: url.lastPathComponent,
                            snippet: url.path,
                            timestamp: mtime)
            }
    }

    /// Upcoming calendar events in the next `daysAhead` days as cards. Reads
    /// EventKit only when full access is already granted (never prompts);
    /// returns [] otherwise — exactly the BriefingComposer pattern.
    private static func upcomingEventCards(daysAhead: Int) -> [ContextCard] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let store = EKEventStore()
        let cal = Calendar.current
        let start = Date()
        let end = cal.date(byAdding: .day, value: max(1, daysAhead), to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(30)
            .map { event in
                let when = event.startDate.formatted(date: .abbreviated, time: .shortened)
                let title = event.title ?? "(untitled)"
                return ContextCard(id: "calendar:\(event.eventIdentifier ?? UUID().uuidString)",
                                   source: .calendar,
                                   title: title,
                                   snippet: "\(when) — \(title)",
                                   timestamp: event.startDate)
            }
    }

    /// Apps open right now, frontmost first — cheap, no permission. Lets Aria
    /// answer "what am I working in?" / "switch back to my editor".
    @MainActor
    private static func appCards(limit: Int) -> [ContextCard] {
        let ws = NSWorkspace.shared
        let frontPID = ws.frontmostApplication?.processIdentifier
        let now = Date()
        return ws.runningApplications
            .filter { $0.activationPolicy == .regular && ($0.localizedName?.isEmpty == false) }
            .prefix(limit)
            .map { app in
                let name = app.localizedName ?? "App"
                let active = app.processIdentifier == frontPID
                return ContextCard(id: "app:\(app.bundleIdentifier ?? name)",
                                   source: .app,
                                   title: name,
                                   snippet: active ? "Active right now" : "Open right now",
                                   timestamp: now)
            }
    }

    /// Recent message previews via a READ-ONLY sqlite3 query on chat.db. Requires
    /// Full Disk Access; silently returns [] without it. Hard-bounded by a short
    /// timeout so a locked/slow DB can never stall a refresh. Never copies the DB.
    nonisolated private static func messageCards(limit: Int) -> [ContextCard] {
        let path = ("~/Library/Messages/chat.db" as NSString).expandingTildeInPath
        guard FileManager.default.isReadableFile(atPath: path) else { return [] }
        let sql = "SELECT COALESCE(text,'') FROM message "
            + "WHERE text IS NOT NULL AND length(text) > 0 "
            + "ORDER BY date DESC LIMIT \(max(1, limit));"
        guard let out = runWithTimeout("/usr/bin/sqlite3", ["-readonly", path, sql], seconds: 2.5) else {
            return []
        }
        let now = Date()
        return out.split(separator: "\n").prefix(limit).enumerated().map { idx, line in
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            return ContextCard(id: "message:\(idx):\(text.prefix(24))",
                               source: .message,
                               title: "Recent message",
                               snippet: String(text.prefix(160)),
                               timestamp: now)
        }
    }

    /// Run a command, capturing stdout, killed if it exceeds `seconds`. Returns
    /// nil on launch failure, timeout, or non-zero exit. Output is expected small.
    nonisolated private static func runWithTimeout(_ launchPath: String, _ args: [String], seconds: Double) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { proc.waitUntilExit(); group.leave() }
        if group.wait(timeout: .now() + seconds) == .timedOut {
            proc.terminate()
            return nil
        }
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    // MARK: Ambient context summary

    /// A short text snippet summarising ambient context (top cards + current
    /// clipboard). Used by the orchestrator's system-prompt builder to ground
    /// the model in what the user is doing right now.
    func contextSummary(query: String = "", limit: Int = 5) async -> String {
        guard isEnabled else { return "" }
        var parts: [String] = []

        // Top matching cards (or just the most-recent ones when no query).
        let matched = query.isEmpty
            ? Array(cards.prefix(limit))
            : Self.rank(query, in: cards, limit: limit)
        if !matched.isEmpty {
            let lines = matched.map { "[\($0.source.rawValue)] \($0.title): \($0.snippet)" }
            parts.append(contentsOf: lines)
        }

        // Clipboard — injected from the poller so we never read NSPasteboard here.
        if let clip = await ClipboardContext.shared.snapshot(), !clip.isEmpty {
            parts.append("Clipboard: \(clip.prefix(200))")
        }

        // Screen OCR — read visible text with a 3 s timeout so a slow capture
        // never blocks context injection. Silently skipped on failure.
        if let ocr = await withScreenOCRTimeout() {
            parts.append("Screen: \(ocr)")
        }

        return parts.joined(separator: "\n")
    }

    // MARK: Screen OCR helper

    /// Attempt to read screen text within a 3 s deadline; returns nil on
    /// timeout, capture failure, or any recognition error.
    private func withScreenOCRTimeout() async -> String? {
        let task = Task<String?, Never> {
            (try? await ScreenOCR.live.readAndTruncate(maxChars: 500))
        }
        // Race the OCR task against a 3-second cancellation.
        let deadline = Task<String?, Never> {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            task.cancel()
            return nil
        }
        let result = await task.value
        deadline.cancel()
        return result
    }

    // MARK: Persistence

    private func save() {
        let encoder = JSONEncoder()
        // Epoch seconds (mirrors KnowledgeIndex): avoids iso8601 fractional-second
        // drift on round-trip.
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(cards) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [ContextCard] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([ContextCard].self, from: data)) ?? []
    }
}
