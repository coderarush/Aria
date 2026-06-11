import Foundation

/// V11 P12 — Focus Mode: "enter focus mode" opens what the work needs, closes
/// the distractions, and starts a tracked session; "end focus mode" recaps
/// what happened from the timeline. A mode is just a deterministic plan (the
/// recipe machinery) plus the session bracket.
struct FocusMode: Codable, Equatable, Sendable {
    var name: String
    var openApps: [String]
    var closeApps: [String]

    /// The deterministic plan: open everything needed, then close distractions.
    func taskSteps() -> [TaskStep] {
        openApps.map { TaskStep(summary: "Open \($0)", executor: .tool("open_app"), input: ["name": $0]) }
        + closeApps.map { TaskStep(summary: "Close \($0)", executor: .tool("quit_app"), input: ["name": $0]) }
    }

    // MARK: presets (V11: Student / Founder / Developer / Custom)

    static let presets: [FocusMode] = [
        FocusMode(name: "student",
                  openApps: ["Notes", "Calendar"],
                  closeApps: ["Messages", "Music"]),
        FocusMode(name: "founder",
                  openApps: ["Calendar", "Mail", "Notes"],
                  closeApps: ["Messages", "Music"]),
        FocusMode(name: "developer",
                  openApps: ["Visual Studio Code", "Terminal"],
                  closeApps: ["Messages", "Mail", "Music"])
    ]

    /// Preset by name; "" or unknown falls back to a sensible default
    /// (distraction-closing only — works for anyone).
    static func preset(named name: String) -> FocusMode {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let hit = presets.first(where: { $0.name == n }) { return hit }
        return FocusMode(name: n.isEmpty ? "focus" : n,
                         openApps: [],
                         closeApps: ["Messages", "Music"])
    }

    // MARK: intents

    /// "start developer focus mode" → "developer"; "enter focus mode" → "";
    /// nil when the command isn't a focus-mode entry at all.
    static func enterIntent(_ command: String) -> String? {
        let c = command.lowercased()
        guard c.contains("focus mode") || c.hasSuffix("focus") else { return nil }
        guard let verb = ["enter", "start", "begin"].first(where: c.contains) else { return nil }
        guard let verbRange = c.range(of: verb),
              let focusRange = c.range(of: "focus") else { return nil }
        guard verbRange.upperBound <= focusRange.lowerBound else { return nil }
        let between = c[verbRange.upperBound..<focusRange.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        return between
    }

    static func isEndIntent(_ command: String) -> Bool {
        let c = command.lowercased()
        guard ["end", "exit", "stop", "finish"].contains(where: c.contains) else { return false }
        return c.contains("focus")
    }
}

/// The active focus session, persisted so a crash mid-session still recaps.
actor FocusSession {
    static let shared = FocusSession()

    struct Record: Codable, Equatable, Sendable {
        let mode: String
        let startedAt: Date
    }

    private let fileURL: URL
    private var current: Record?

    init(fileURL: URL? = nil) {
        let url = fileURL ?? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("focus-session.json")
        self.fileURL = url
        self.current = Self.load(from: url)
    }

    func begin(mode: String, at date: Date = Date()) {
        current = Record(mode: mode, startedAt: date)
        save()
    }

    func active() -> Record? { current }

    /// Ends the session and returns it (nil when none was running).
    @discardableResult
    func end(at date: Date = Date()) -> Record? {
        defer { current = nil; save() }
        return current
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let current, let data = try? encoder.encode(current) {
            try? data.write(to: fileURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func load(from url: URL) -> Record? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Record.self, from: data)
    }
}
