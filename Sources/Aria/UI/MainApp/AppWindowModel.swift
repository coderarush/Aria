import SwiftUI
import Combine

/// The five top-level destinations of Aria's main window. Plain eager switch —
/// deliberately no NavigationSplitView (see SettingsView header for the macOS 26
/// Form/List optimizer-crash note that governs this whole window).
enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case home          = "Home"
    case conversations = "Conversations"
    case activity      = "Activity"
    case insights      = "Insights"
    case connectors    = "Connectors"
    case settings      = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home:          return "house"
        case .conversations: return "bubble.left.and.bubble.right"
        case .activity:      return "list.bullet.rectangle"
        case .insights:      return "sparkles"
        case .connectors:    return "puzzlepiece.extension"
        case .settings:      return "gearshape"
        }
    }
}

/// A read-only view-model snapshot of a single conversation turn, decoupled from
/// the `ConversationTurn` actor model so the view layer stays pure + previewable.
struct ConversationRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let transcript: String
    let response: String

    /// First non-empty line of the user's transcript — the row title.
    var title: String {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Voice request" : t
    }

    /// Short snippet of Aria's reply for the row subtitle.
    var snippet: String {
        AppWindowModel.oneLine(response, max: 100)
    }
}

/// One day's worth of activity entries, for the grouped Activity pane.
struct ActivityDayGroup: Identifiable, Equatable, Sendable {
    let id: String            // the formatted day label, also the stable id
    let day: Date
    let entries: [ActivityEntry]
}

/// A connector card descriptor. OAuth-backed cards (those with a `connectorID`)
/// drive the live `ConnectorStore`; the rest are non-OAuth placeholders that
/// ship as "Coming soon".
struct ConnectorInfo: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case comingSoon        // no backend (Apple Mail / iCloud, for now)
        case notConfigured     // OAuth-backed, but no client ID yet
        case available         // configured — ready to connect
        case connected
    }
    let id: String
    let name: String
    let blurb: String
    let icon: String          // SF Symbol
    let tint: Color
    /// The OAuth backend this card drives, if any. nil = non-OAuth placeholder.
    var connectorID: ConnectorID? = nil
    var status: Status = .comingSoon
}

/// Pure, view-independent logic for the Connectors setup flow. Lives here (not in
/// the view) so it can be unit-tested without a window or the Keychain: client-ID
/// trimming/validation, whether a provider needs a secret, the status→button-label
/// mapping, the connected-account hint, and the per-provider setup steps.
///
/// No network, no SwiftUI — every method is `nonisolated` and deterministic.
enum ConnectorSetup {

    // MARK: Client-ID / secret validation

    /// Trim surrounding whitespace/newlines from a pasted credential.
    static func sanitize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A client ID is acceptable once it's non-empty after trimming. We don't
    /// hard-validate the format (providers differ — Google's ends in
    /// `.apps.googleusercontent.com`, Notion/Slack use opaque IDs), so a blank or
    /// whitespace-only paste is the only rejection.
    static func isValidClientID(_ raw: String) -> Bool {
        !sanitize(raw).isEmpty
    }

    /// True when the provider's OAuth flow requires a client *secret* in addition
    /// to the client ID. Google native apps use PKCE without a secret; Notion and
    /// Slack issue a confidential secret that must be supplied.
    static func requiresSecret(_ id: ConnectorID) -> Bool {
        switch id {
        case .google: return false
        case .notion, .slack: return true
        }
    }

    /// Whether the Save action should be enabled given the current field values.
    /// The secret field only gates Save for providers that require one.
    static func canSave(_ id: ConnectorID, clientID: String, secret: String) -> Bool {
        guard isValidClientID(clientID) else { return false }
        if requiresSecret(id) { return isValidClientID(secret) }
        return true
    }

    // MARK: Keychain account keys (mirrors ConnectorProvider's convention)

    static func clientIDAccount(_ id: ConnectorID) -> String {
        "connector_\(id.rawValue)_client_id"
    }

    static func clientSecretAccount(_ id: ConnectorID) -> String {
        "connector_\(id.rawValue)_client_secret"
    }

    // MARK: Status → presentation

    /// Resolve the card's display status from a live backend snapshot. A nil
    /// `connectorID` (non-OAuth placeholder) or a missing snapshot is "coming
    /// soon"; otherwise connected ▸ configured-but-not-connected (ready) ▸ needs
    /// a client ID.
    static func status(connectorID: ConnectorID?,
                       live: ConnectorStatus?) -> ConnectorInfo.Status {
        guard connectorID != nil, let live else { return .comingSoon }
        if live.isConnected { return .connected }
        return live.isConfigured ? .available : .notConfigured
    }

    /// The primary button's label for a status (busy spinners handled by the view).
    static func buttonLabel(for status: ConnectorInfo.Status) -> String {
        switch status {
        case .connected:                  return "Disconnect"
        case .available:                  return "Connect"
        case .notConfigured:              return "Add client ID"
        case .comingSoon:                 return "Coming soon"
        }
    }

    /// The status pill's text.
    static func pillLabel(for status: ConnectorInfo.Status) -> String {
        switch status {
        case .connected:     return "Connected"
        case .available:     return "Ready"
        case .notConfigured: return "Setup needed"
        case .comingSoon:    return "Coming soon"
        }
    }

    /// A short connected-account hint from the granted scopes / expiry, e.g.
    /// "Gmail · Calendar" for Google, or a scope count otherwise. Never shows a
    /// token. Returns nil when there's nothing useful to say.
    static func connectedHint(_ status: ConnectorStatus) -> String? {
        guard status.isConnected else { return nil }
        let friendly = status.scopes.compactMap(friendlyScope)
        if !friendly.isEmpty {
            // De-dupe while preserving order (Gmail + Calendar, not Gmail twice).
            var seen = Set<String>()
            let unique = friendly.filter { seen.insert($0).inserted }
            return unique.joined(separator: " · ")
        }
        if !status.scopes.isEmpty {
            return status.scopes.count == 1 ? "1 permission granted"
                                            : "\(status.scopes.count) permissions granted"
        }
        return "Linked"
    }

    /// Map a raw OAuth scope string to a short human label, or nil if unknown.
    static func friendlyScope(_ scope: String) -> String? {
        let s = scope.lowercased()
        if s.contains("gmail")    { return "Gmail" }
        if s.contains("calendar") { return "Calendar" }
        if s.contains("drive")    { return "Drive" }
        if s.contains("chat:write") || s.contains("channels") { return "Slack" }
        if s.contains("users:read") { return "Members" }
        return nil
    }

    // MARK: Setup help

    /// The 3–4 step "how do I get a client ID?" guide for a provider.
    static func setupSteps(for id: ConnectorID) -> [String] {
        switch id {
        case .google:
            return [
                "Open Google Cloud Console → APIs & Services → Credentials.",
                "Create an OAuth client ID, application type “Desktop app”.",
                "Enable the Gmail API and Google Calendar API for the project.",
                "Copy the Client ID and paste it above (no secret needed — Aria uses PKCE)."
            ]
        case .notion:
            return [
                "Open notion.so/my-integrations and create a new integration.",
                "Set the OAuth redirect URI to http://127.0.0.1 (loopback).",
                "Copy the OAuth client ID and client secret.",
                "Paste both above, then share the pages you want Aria to reach."
            ]
        case .slack:
            return [
                "Open api.slack.com/apps and create a new app.",
                "Under OAuth & Permissions add a redirect URL of http://127.0.0.1.",
                "Add the channels:read, chat:write and users:read scopes.",
                "Copy the Client ID and Client Secret and paste both above."
            ]
        }
    }

    /// A one-line label for where to get credentials, used as the link/hint title.
    static func consoleName(for id: ConnectorID) -> String {
        switch id {
        case .google: return "Google Cloud Console"
        case .notion: return "Notion integrations"
        case .slack:  return "Slack API dashboard"
        }
    }
}

/// Backing model for the main window. `@MainActor` and an `ObservableObject` so the
/// SwiftUI shell can observe it. Loads read-only snapshots from the conversation /
/// activity / journal stores; never mutates them. All formatting/grouping/filtering
/// lives in pure static helpers so it can be unit-tested without a window.
@MainActor
final class AppWindowModel: ObservableObject {
    @Published var section: AppSection = .home
    @Published var conversationQuery: String = ""
    @Published var selectedConversationID: UUID?

    @Published private(set) var conversations: [ConversationRow] = []
    @Published private(set) var activity: [ActivityEntry] = []
    @Published private(set) var workEntries: [WorkEntry] = []
    @Published private(set) var isLoading = true

    private let conversationMemory: ConversationMemory
    private let activityLog: ActivityLog
    private let journal: WorkJournal

    init(conversationMemory: ConversationMemory = ConversationMemory(),
         activityLog: ActivityLog = .shared,
         journal: WorkJournal = .shared) {
        self.conversationMemory = conversationMemory
        self.activityLog = activityLog
        self.journal = journal
    }

    /// Pull fresh read-only snapshots from the three stores. Safe to call on
    /// appear and again whenever the window is re-shown.
    func refresh() async {
        isLoading = true
        async let turns = conversationMemory.turns
        async let recentActivity = activityLog.recent(200)
        async let recentWork = journal.recent(200)

        let loadedTurns = await turns
        conversations = loadedTurns
            .map { ConversationRow(id: $0.id, timestamp: $0.timestamp,
                                   transcript: $0.transcript, response: $0.responseMessage) }
            .reversed()                       // newest first
        activity = await recentActivity
        workEntries = await recentWork
        if selectedConversationID == nil { selectedConversationID = conversations.first?.id }
        isLoading = false
    }

    // MARK: Derived (computed off the snapshots)

    var filteredConversations: [ConversationRow] {
        Self.filterConversations(conversations, query: conversationQuery)
    }

    var selectedConversation: ConversationRow? {
        guard let id = selectedConversationID else { return filteredConversations.first }
        return conversations.first { $0.id == id } ?? filteredConversations.first
    }

    var activityByDay: [ActivityDayGroup] {
        Self.groupByDay(activity)
    }

    /// Headline counts for the Home dashboard.
    var conversationCount: Int { conversations.count }
    var tasksCompleted: Int { workEntries.filter { $0.ok }.count }
    var actionsTaken: Int { activity.count }

    // MARK: - Pure helpers (unit-tested)

    /// Filter conversations by a case-insensitive substring over transcript +
    /// response. Empty/whitespace query returns the list unchanged.
    nonisolated static func filterConversations(_ rows: [ConversationRow], query: String) -> [ConversationRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter {
            $0.transcript.lowercased().contains(q) || $0.response.lowercased().contains(q)
        }
    }

    /// Group activity entries by calendar day, newest day first, entries within a
    /// day newest first. Stable day label is used as the group id.
    nonisolated static func groupByDay(_ entries: [ActivityEntry],
                                       calendar: Calendar = .current) -> [ActivityDayGroup] {
        let buckets = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return buckets.keys.sorted(by: >).map { day in
            let sorted = (buckets[day] ?? []).sorted { $0.date > $1.date }
            return ActivityDayGroup(id: dayLabel(day, calendar: calendar), day: day, entries: sorted)
        }
    }

    /// "Today" / "Yesterday" / "Mon, Jun 9" — a friendly day header.
    nonisolated static func dayLabel(_ day: Date, calendar: Calendar = .current,
                                     now: Date = Date()) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return f.string(from: day)
    }

    /// Compact relative time, e.g. "2m ago", "3h ago", "just now".
    nonisolated static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let secs = now.timeIntervalSince(date)
        if secs < 45 { return "just now" }
        if secs < 90 { return "1m ago" }
        if secs < 3600 { return "\(Int(secs / 60))m ago" }
        if secs < 5400 { return "1h ago" }
        if secs < 86_400 { return "\(Int(secs / 3600))h ago" }
        if secs < 172_800 { return "yesterday" }
        if secs < 604_800 { return "\(Int(secs / 86_400))d ago" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }

    /// Collapse to a single trimmed line, capped with an ellipsis.
    nonisolated static func oneLine(_ text: String, max: Int = 120) -> String {
        let line = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.count > max else { return line }
        return String(line.prefix(max)) + "…"
    }

    /// A time-of-day greeting for the Home hero.
    nonisolated static func greeting(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: now) {
        case 0..<5:   return "Still up"
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    // MARK: Connectors catalog

    /// The integrations Aria is built to speak to. Ordered to put the heaviest
    /// hitters first. Status is static "Coming soon" until the OAuth effort lands.
    static let connectorCatalog: [ConnectorInfo] = [
        ConnectorInfo(id: "gmail", name: "Gmail",
                      blurb: "Triage, draft and send mail by voice.",
                      icon: "envelope.fill", tint: Color(red: 0.92, green: 0.27, blue: 0.21),
                      connectorID: .google),
        ConnectorInfo(id: "gcal", name: "Google Calendar",
                      blurb: "See your day, schedule and reschedule.",
                      icon: "calendar", tint: Color(red: 0.26, green: 0.52, blue: 0.96),
                      connectorID: .google),
        ConnectorInfo(id: "notion", name: "Notion",
                      blurb: "Capture notes and update pages hands-free.",
                      icon: "doc.text.fill", tint: Color(red: 0.13, green: 0.13, blue: 0.15),
                      connectorID: .notion),
        ConnectorInfo(id: "slack", name: "Slack",
                      blurb: "Catch up and reply across your channels.",
                      icon: "number.square.fill", tint: Color(red: 0.36, green: 0.16, blue: 0.55),
                      connectorID: .slack),
        ConnectorInfo(id: "applemail", name: "Apple Mail",
                      blurb: "Work your inbox without lifting a finger.",
                      icon: "envelope.badge.fill", tint: Color(red: 0.20, green: 0.56, blue: 0.99)),
        ConnectorInfo(id: "icloud", name: "iCloud",
                      blurb: "Reach your reminders, notes and files.",
                      icon: "cloud.fill", tint: Color(red: 0.45, green: 0.72, blue: 0.95)),
    ]
}
