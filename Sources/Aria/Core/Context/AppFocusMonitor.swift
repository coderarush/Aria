import Foundation
import AppKit

/// "Aria knows what you're *in* right now." A passive monitor of the frontmost
/// application: it subscribes to `NSWorkspace.didActivateApplicationNotification`
/// and tracks which app has focus and since when — so the orchestrator can ground
/// answers in the app the user is actually working in, not a once-per-tick
/// snapshot that goes stale the moment they switch windows.
///
/// Free and permission-less: app names come straight from `NSRunningApplication`,
/// no Accessibility or Screen-Recording access required. Aria's own panels are
/// ignored so summoning the orb never counts as "switching apps".
actor AppFocusMonitor {
    static let shared = AppFocusMonitor()

    /// The currently-focused app and when it gained focus.
    struct Focus: Equatable {
        let appName: String
        let bundleId: String?
        let since: Date
    }

    private(set) var current: Focus?
    private var observer: NSObjectProtocol?

    init() {}

    /// Begin observing focus changes (idempotent). Seeds with the current
    /// frontmost app so we're never blank until the first switch.
    func start() async {
        guard observer == nil else { return }
        let nc = NSWorkspace.shared.notificationCenter
        observer = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            let name = app.localizedName ?? "an app"
            let bundle = app.bundleIdentifier
            Task { await self.noteActivation(appName: name, bundleId: bundle) }
        }
        if let front = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication }),
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            noteActivation(appName: front.localizedName ?? "an app", bundleId: front.bundleIdentifier)
        }
    }

    /// Record that `appName` gained focus. Re-activating the same app keeps the
    /// original `since` (one continuous focus session); switching apps resets it.
    func noteActivation(appName: String, bundleId: String?, at date: Date = Date()) {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let c = current, c.bundleId == bundleId, c.appName == name { return }
        current = Focus(appName: name, bundleId: bundleId, since: date)
    }

    func snapshot() -> Focus? { current }

    /// One-line ambient summary for the system prompt, or nil if nothing focused.
    func summaryLine(now: Date = Date()) -> String? {
        guard let c = current else { return nil }
        return Self.focusLine(appName: c.appName, since: c.since, now: now)
    }

    /// Pure, testable formatter: "Right now you're working in Xcode (12m)."
    /// Returns nil for a blank app name.
    static func focusLine(appName: String, since: Date, now: Date) -> String? {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let secs = max(0, now.timeIntervalSince(since))
        let span: String
        if secs < 60 {
            span = "just switched"
        } else if secs < 3600 {
            span = "\(Int(secs / 60))m"
        } else {
            let h = Int(secs / 3600)
            let m = Int(secs.truncatingRemainder(dividingBy: 3600) / 60)
            span = "\(h)h \(m)m"
        }
        return "Right now you're working in \(name) (\(span))."
    }
}
