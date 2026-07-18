import Foundation

/// A Perceive-stage producer: folds fresh signal data into the presence
/// context each evaluation. Cheap and local-first — no LLM calls here, ever
/// (Live Loop design 2026-06-24).
protocol LiveSignal: Sendable {
    func apply(to context: PresenceContext, now: Date) async -> PresenceContext
}

/// Time-of-day + "has today's brief run" — powers `DailyBriefRule`.
struct ClockSignal: LiveSignal {
    let calendar: Calendar
    /// Reads the persisted day stamp (injected so tests need no UserDefaults).
    let briefAlreadyRan: @Sendable (Date) -> Bool

    init(calendar: Calendar = .current,
         briefAlreadyRan: @escaping @Sendable (Date) -> Bool) {
        self.calendar = calendar
        self.briefAlreadyRan = briefAlreadyRan
    }

    func apply(to context: PresenceContext, now: Date) async -> PresenceContext {
        var next = context
        next.hour = calendar.component(.hour, from: now)
        next.dailyBriefAlreadyRanToday = briefAlreadyRan(now)
        return next
    }
}

/// Next calendar event + minutes-until — powers `MeetingPrepRule`. The fetcher
/// is injected (live wiring uses the same EventKit query Proactive Presence
/// already uses; it never prompts for access from a background tick).
struct CalendarSignal: LiveSignal {
    let fetchUpcoming: @Sendable (Date) async -> [UpcomingEvent]

    init(fetchUpcoming: @escaping @Sendable (Date) async -> [UpcomingEvent]) {
        self.fetchUpcoming = fetchUpcoming
    }

    func apply(to context: PresenceContext, now: Date) async -> PresenceContext {
        var next = context
        guard let event = await fetchUpcoming(now).min(by: { $0.start < $1.start }) else {
            return next
        }
        next.minutesUntilNextMeeting = max(0, Int(event.start.timeIntervalSince(now) / 60))
        next.nextEventTitle = event.title
        return next
    }
}

/// Unread-mail delta — powers `InboxTriageRule`. Actor because it remembers
/// the previous count between evaluations. The fetcher returns the current
/// unread count, or nil when mail isn't reachable (not connected / offline) —
/// nil never fires the rule. Polls at most once per `minInterval`.
actor MailSignal: LiveSignal {
    private let fetchUnreadCount: @Sendable () async -> Int?
    private let minInterval: TimeInterval
    private var lastCount: Int?
    private var lastFetch: Date?
    private var lastDelta = 0

    init(minInterval: TimeInterval = 5 * 60,
         fetchUnreadCount: @escaping @Sendable () async -> Int?) {
        self.minInterval = minInterval
        self.fetchUnreadCount = fetchUnreadCount
    }

    func apply(to context: PresenceContext, now: Date) async -> PresenceContext {
        var next = context
        if let last = lastFetch, now.timeIntervalSince(last) < minInterval {
            next.newUnreadMail = lastDelta
            return next
        }
        lastFetch = now
        guard let count = await fetchUnreadCount() else {
            lastDelta = 0
            next.newUnreadMail = 0
            return next
        }
        // First observation is a baseline, not "new mail".
        let delta = lastCount.map { max(0, count - $0) } ?? 0
        lastCount = count
        lastDelta = delta
        next.newUnreadMail = delta
        return next
    }
}

/// Frontmost-app churn + idle time — powers `ScreenCoPilotRule`. App
/// activations are pushed in from NSWorkspace notifications (event-driven,
/// zero polling); the signal keeps a short ring buffer and reports when the
/// user ping-pongs between the same two apps.
actor ScreenActivitySignal: LiveSignal {
    /// Sliding window over which switches count.
    private let window: TimeInterval
    private let idleSeconds: @Sendable () -> TimeInterval
    private var activations: [(app: String, at: Date)] = []

    init(window: TimeInterval = 120,
         idleSeconds: @escaping @Sendable () -> TimeInterval = { 0 }) {
        self.window = window
        self.idleSeconds = idleSeconds
    }

    /// Called from the workspace-activation observer.
    func noteActivation(app: String, at: Date) {
        guard !app.isEmpty else { return }
        // Only record actual switches, not repeated foreground pings.
        if activations.last?.app == app { return }
        activations.append((app, at))
        let cutoff = at.addingTimeInterval(-window)
        activations.removeAll { $0.at < cutoff }
        if activations.count > 64 { activations.removeFirst(activations.count - 64) }
    }

    func apply(to context: PresenceContext, now: Date) async -> PresenceContext {
        var next = context
        next.idleSeconds = idleSeconds()
        let cutoff = now.addingTimeInterval(-window)
        let recent = activations.filter { $0.at >= cutoff }
        next.appPingPong = Self.pingPong(in: recent.map(\.app))
        return next
    }

    /// A ping-pong is an alternating A,B,A,B… run. Returns the dominant pair
    /// and how many switches it made inside the window.
    static func pingPong(in apps: [String]) -> AppPingPong? {
        guard apps.count >= 4 else { return nil }
        var best: AppPingPong?
        var runPair: (String, String)? = nil
        var runLength = 1
        for i in 1..<apps.count {
            let pair = (min(apps[i - 1], apps[i]), max(apps[i - 1], apps[i]))
            if let current = runPair, current == pair {
                runLength += 1
            } else {
                runPair = pair
                runLength = 1
            }
            if runLength >= (best?.count ?? 3) {
                best = AppPingPong(appA: pair.0, appB: pair.1, count: runLength)
            }
        }
        return best
    }
}
