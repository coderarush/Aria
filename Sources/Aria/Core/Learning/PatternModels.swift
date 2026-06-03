import Foundation

enum Weekday: Int, Codable, CaseIterable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    init(date: Date, calendar: Calendar = .current) {
        let comp = calendar.component(.weekday, from: date)
        self = Weekday(rawValue: comp) ?? .sunday
    }
}

/// What causes a pattern's action to fire.
enum PatternTrigger: Codable, Equatable {
    case timeOfDay(hour: Int, minute: Int, days: Set<Weekday>)
    case appLaunched(bundleId: String)
    case appQuit(bundleId: String)
    case fileModified(path: String)
    indirect case compound([PatternTrigger])
}

/// What Friday does when a pattern fires.
enum PatternAction: Codable, Equatable {
    case runSavedCommand(String)
    case runGeneratedScript(toolID: UUID)
    case askUser(String)
}

enum PatternStatus: String, Codable {
    case observing, suggested, approved, running, paused, suppressed
}

enum ApprovalMode: String, Codable {
    case auto          // run silently
    case previewFirst  // run but show preview before finalizing
}

/// A learned habit. Stored in patterns.json.
struct BehaviorPattern: Codable, Identifiable, Equatable {
    let id: UUID
    var description: String
    var trigger: PatternTrigger
    var action: PatternAction
    var confidence: Double
    var occurrences: [Date]
    var status: PatternStatus
    var approvalMode: ApprovalMode?
    var lastFired: Date?
    var suggestionCount: Int    // how many times we've asked the user

    init(id: UUID = UUID(),
         description: String,
         trigger: PatternTrigger,
         action: PatternAction,
         confidence: Double,
         occurrences: [Date],
         status: PatternStatus = .observing,
         approvalMode: ApprovalMode? = nil,
         lastFired: Date? = nil,
         suggestionCount: Int = 0) {
        self.id = id
        self.description = description
        self.trigger = trigger
        self.action = action
        self.confidence = confidence
        self.occurrences = occurrences
        self.status = status
        self.approvalMode = approvalMode
        self.lastFired = lastFired
        self.suggestionCount = suggestionCount
    }
}

// MARK: Observation events

struct CommandEvent: Codable, Equatable {
    let command: String
    let timestamp: Date
}

struct AppEvent: Codable, Equatable {
    enum Kind: String, Codable { case launched, quit, activated }
    let bundleId: String
    let kind: Kind
    let timestamp: Date
}

struct FileEvent: Codable, Equatable {
    let path: String       // metadata only — never contents
    let timestamp: Date
}
