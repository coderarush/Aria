import XCTest
@testable import Aria

// MARK: - Playbook resolution

final class PlaybookLibraryTests: XCTestCase {

    func testResolvesMeetingPrepWithBoundInputs() {
        let ref = PlaybookRef(id: PlaybookLibrary.meetingPrep,
                              inputs: ["event_title": "Design review", "minutes": "10"])
        let resolved = PlaybookLibrary.resolve(ref)
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved!.command.contains("Design review"))
        XCTAssertTrue(resolved!.offer.contains("10 minutes"))
        XCTAssertFalse(resolved!.command.contains("{{"))
    }

    func testUnboundPlaceholderFailsResolution() {
        let ref = PlaybookRef(id: PlaybookLibrary.meetingPrep,
                              inputs: ["event_title": "Standup"])   // missing minutes
        XCTAssertNil(PlaybookLibrary.resolve(ref))
    }

    func testUnknownPlaybookFailsResolution() {
        XCTAssertNil(PlaybookLibrary.resolve(PlaybookRef(id: "nope")))
    }

    func testInputFreePlaybooksResolve() {
        XCTAssertNotNil(PlaybookLibrary.resolve(PlaybookRef(id: PlaybookLibrary.dailyBrief)))
        XCTAssertNotNil(PlaybookLibrary.resolve(PlaybookRef(id: PlaybookLibrary.inboxTriage)))
    }
}

// MARK: - Recognizers

final class LiveRecognizerTests: XCTestCase {

    func testMeetingPrepFiresInsideWindowWithPlaybook() {
        let context = PresenceContext(minutesUntilNextMeeting: 10, nextEventTitle: "1:1 with Sam")
        let opportunity = MeetingPrepRule().evaluate(context)
        XCTAssertNotNil(opportunity)
        XCTAssertEqual(opportunity?.playbook?.id, PlaybookLibrary.meetingPrep)
        XCTAssertEqual(opportunity?.playbook?.inputs["event_title"], "1:1 with Sam")
        XCTAssertEqual(opportunity?.playbook?.inputs["minutes"], "10")
    }

    func testMeetingPrepSilentOutsideWindowOrWithoutTitle() {
        XCTAssertNil(MeetingPrepRule().evaluate(
            PresenceContext(minutesUntilNextMeeting: 40, nextEventTitle: "Later")))
        XCTAssertNil(MeetingPrepRule().evaluate(
            PresenceContext(minutesUntilNextMeeting: 5)))
        XCTAssertNil(MeetingPrepRule().evaluate(PresenceContext()))
    }

    func testInboxTriageFiresOnlyOnNewMail() {
        XCTAssertNil(InboxTriageRule().evaluate(PresenceContext(newUnreadMail: 0)))
        let opportunity = InboxTriageRule().evaluate(PresenceContext(newUnreadMail: 3))
        XCTAssertEqual(opportunity?.playbook?.id, PlaybookLibrary.inboxTriage)
    }

    func testScreenCoPilotNeedsEnoughSwitches() {
        let few = PresenceContext(appPingPong: AppPingPong(appA: "Numbers", appB: "Safari", count: 3))
        XCTAssertNil(ScreenCoPilotRule().evaluate(few))
        let many = PresenceContext(appPingPong: AppPingPong(appA: "Numbers", appB: "Safari", count: 7))
        let opportunity = ScreenCoPilotRule().evaluate(many)
        XCTAssertEqual(opportunity?.playbook?.id, PlaybookLibrary.screenCoPilot)
        XCTAssertEqual(opportunity?.playbook?.inputs["app_a"], "Numbers")
    }

    func testDailyBriefFiresMorningOnceOnly() {
        XCTAssertNotNil(DailyBriefRule().evaluate(
            PresenceContext(hour: 8, dailyBriefAlreadyRanToday: false)))
        XCTAssertNil(DailyBriefRule().evaluate(
            PresenceContext(hour: 8, dailyBriefAlreadyRanToday: true)))
        XCTAssertNil(DailyBriefRule().evaluate(
            PresenceContext(hour: 15, dailyBriefAlreadyRanToday: false)))
    }
}

// MARK: - Store

final class LiveLoopStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: LiveLoopStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.liveloop.store")!
        defaults.removePersistentDomain(forName: "test.liveloop.store")
        store = LiveLoopStore(defaults: defaults)
    }

    func testCooldownGatesRefires() {
        let now = Date()
        XCTAssertFalse(store.isCoolingDown(PlaybookLibrary.inboxTriage, now: now))
        store.markFired(PlaybookLibrary.inboxTriage, now: now)
        XCTAssertTrue(store.isCoolingDown(PlaybookLibrary.inboxTriage, now: now.addingTimeInterval(30 * 60)))
        XCTAssertFalse(store.isCoolingDown(PlaybookLibrary.inboxTriage, now: now.addingTimeInterval(61 * 60)))
    }

    func testSnoozeAndNever() {
        let now = Date()
        store.snooze(PlaybookLibrary.dailyBrief, until: now.addingTimeInterval(3600))
        XCTAssertTrue(store.isSnoozed(PlaybookLibrary.dailyBrief, now: now))
        XCTAssertFalse(store.isSnoozed(PlaybookLibrary.dailyBrief, now: now.addingTimeInterval(3601)))

        store.setNever(PlaybookLibrary.screenCoPilot)
        XCTAssertTrue(store.isNever(PlaybookLibrary.screenCoPilot))
        store.clearNever(PlaybookLibrary.screenCoPilot)
        XCTAssertFalse(store.isNever(PlaybookLibrary.screenCoPilot))
    }

    func testBriefDayStamp() {
        let now = Date()
        XCTAssertFalse(store.briefAlreadyRan(on: now))
        store.markBriefRan(on: now)
        XCTAssertTrue(store.briefAlreadyRan(on: now))
        XCTAssertFalse(store.briefAlreadyRan(on: now.addingTimeInterval(86_400)))
    }
}

// MARK: - Signals

final class LiveSignalTests: XCTestCase {

    func testClockSignalSetsHourAndBriefFlag() async {
        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 2; components.hour = 7
        let morning = Calendar.current.date(from: components)!
        let signal = ClockSignal(briefAlreadyRan: { _ in false })
        let context = await signal.apply(to: PresenceContext(), now: morning)
        XCTAssertEqual(context.hour, 7)
        XCTAssertFalse(context.dailyBriefAlreadyRanToday)
    }

    func testCalendarSignalPicksSoonestEvent() async {
        let now = Date()
        let signal = CalendarSignal { _ in
            [UpcomingEvent(id: "b", title: "Later", start: now.addingTimeInterval(3000)),
             UpcomingEvent(id: "a", title: "Soon", start: now.addingTimeInterval(600))]
        }
        let context = await signal.apply(to: PresenceContext(), now: now)
        XCTAssertEqual(context.nextEventTitle, "Soon")
        XCTAssertEqual(context.minutesUntilNextMeeting, 10)
    }

    func testMailSignalBaselinesThenReportsDelta() async {
        let counts = Counter([4, 7])
        let signal = MailSignal(minInterval: 0) { await counts.next() }
        let now = Date()
        // First fetch is a baseline — no "new mail".
        var context = await signal.apply(to: PresenceContext(), now: now)
        XCTAssertEqual(context.newUnreadMail, 0)
        // Second fetch reports the delta.
        context = await signal.apply(to: PresenceContext(), now: now.addingTimeInterval(1))
        XCTAssertEqual(context.newUnreadMail, 3)
    }

    func testMailSignalNilFetchNeverFires() async {
        let signal = MailSignal(minInterval: 0) { nil }
        let context = await signal.apply(to: PresenceContext(newUnreadMail: 9), now: Date())
        XCTAssertEqual(context.newUnreadMail, 0)
    }

    func testPingPongDetection() {
        let apps = ["Numbers", "Safari", "Numbers", "Safari", "Numbers", "Safari", "Numbers"]
        let pingPong = ScreenActivitySignal.pingPong(in: apps)
        XCTAssertEqual(pingPong?.count, 6)
        XCTAssertEqual(Set([pingPong?.appA, pingPong?.appB].compactMap { $0 }),
                       Set(["Numbers", "Safari"]))
        XCTAssertNil(ScreenActivitySignal.pingPong(in: ["A", "B", "C", "D", "E"]))
    }

    func testScreenActivitySignalWindowsActivations() async {
        let signal = ScreenActivitySignal(window: 120)
        let now = Date()
        for i in 0..<8 {
            await signal.noteActivation(app: i.isMultiple(of: 2) ? "Xcode" : "Slack",
                                        at: now.addingTimeInterval(Double(i)))
        }
        let context = await signal.apply(to: PresenceContext(), now: now.addingTimeInterval(8))
        XCTAssertNotNil(context.appPingPong)
        XCTAssertGreaterThanOrEqual(context.appPingPong!.count, 6)
        // Far in the future, the window is empty.
        let later = await signal.apply(to: PresenceContext(), now: now.addingTimeInterval(600))
        XCTAssertNil(later.appPingPong)
    }
}

/// Async-safe scripted value source for fakes.
actor Counter {
    private var values: [Int]
    init(_ values: [Int]) { self.values = values }
    func next() -> Int? { values.isEmpty ? nil : values.removeFirst() }
}

// MARK: - The loop

final class LiveLoopEvaluateTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.liveloop.loop")!
        defaults.removePersistentDomain(forName: "test.liveloop.loop")
    }

    /// A context signal that returns a fixed context regardless of input.
    private struct FixedSignal: LiveSignal {
        let context: PresenceContext
        func apply(to _: PresenceContext, now _: Date) async -> PresenceContext { context }
    }

    private func makeLoop(context: PresenceContext,
                          rules: [any OpportunityRule],
                          settings: LiveLoopSettings? = nil,
                          proactive: ProactiveSettings? = nil,
                          lowPower: Bool = false,
                          canSurface: Bool = true,
                          now: Date = Date(),
                          acted: Recorder = Recorder(),
                          offered: Recorder = Recorder(),
                          remembered: Recorder = Recorder()) -> LiveLoop {
        let base = LiveLoopSettings(enabled: true, tiers: [:], pauseInLowPower: true, tickSeconds: 45)
        let proactiveBase = ProactiveSettings(enabled: true, sourceEnabled: [:],
                                              quietHoursEnabled: false,
                                              quietHours: QuietHours(startHour: 22, endHour: 7))
        return LiveLoop(deps: .init(
            signals: [FixedSignal(context: context)],
            rules: rules,
            settings: { settings ?? base },
            proactiveSettings: { proactive ?? proactiveBase },
            store: LiveLoopStore(defaults: defaults),
            isLowPower: { lowPower },
            canSurface: { canSurface },
            act: { command, _ in await acted.append(command) },
            offer: { suggestion in await offered.append(suggestion.spokenLine) },
            remember: { line in await remembered.append(line) },
            now: { now }))
    }

    func testAutoTierActsAndRemembers() async {
        let acted = Recorder(); let remembered = Recorder()
        let loop = makeLoop(
            context: PresenceContext(minutesUntilNextMeeting: 5, nextEventTitle: "Board sync"),
            rules: [MeetingPrepRule()], acted: acted, remembered: remembered)
        let outcome = await loop.evaluate()
        guard case .acted(let id, let command) = outcome else {
            return XCTFail("expected acted, got \(outcome)")
        }
        XCTAssertEqual(id, PlaybookLibrary.meetingPrep)
        XCTAssertTrue(command.contains("Board sync"))
        let commands = await acted.lines
        XCTAssertEqual(commands.count, 1)
        let memories = await remembered.lines
        XCTAssertTrue(memories.first?.contains("Meeting prep") == true)
    }

    func testConfirmTierOffersSuggestion() async {
        let offered = Recorder()
        let loop = makeLoop(context: PresenceContext(newUnreadMail: 2),
                            rules: [InboxTriageRule()], offered: offered)
        let outcome = await loop.evaluate()
        guard case .offered(let id, let suggestion) = outcome else {
            return XCTFail("expected offered, got \(outcome)")
        }
        XCTAssertEqual(id, PlaybookLibrary.inboxTriage)
        XCTAssertEqual(suggestion.dedupeKey, "liveloop.inbox_triage")
        if case .runCommand(let cmd) = suggestion.action {
            XCTAssertTrue(cmd.contains("do NOT send"))
        } else {
            XCTFail("expected runCommand action")
        }
        let lines = await offered.lines
        XCTAssertEqual(lines.count, 1)
    }

    func testOffTierAndDisabledLoopStayIdle() async {
        let context = PresenceContext(minutesUntilNextMeeting: 5, nextEventTitle: "X")
        let offSettings = LiveLoopSettings(
            enabled: true, tiers: [PlaybookLibrary.meetingPrep: .off],
            pauseInLowPower: true, tickSeconds: 45)
        var outcome = await makeLoop(context: context, rules: [MeetingPrepRule()],
                                     settings: offSettings).evaluate()
        XCTAssertEqual(outcome, .idle)

        let disabled = LiveLoopSettings(enabled: false, tiers: [:],
                                        pauseInLowPower: true, tickSeconds: 45)
        outcome = await makeLoop(context: context, rules: [MeetingPrepRule()],
                                 settings: disabled).evaluate()
        XCTAssertEqual(outcome, .idle)
    }

    func testLowPowerPausesLoop() async {
        let loop = makeLoop(
            context: PresenceContext(minutesUntilNextMeeting: 5, nextEventTitle: "X"),
            rules: [MeetingPrepRule()], lowPower: true)
        let outcome = await loop.evaluate()
        XCTAssertEqual(outcome, .idle)
    }

    func testBusySurfaceDefersWithoutBurningCooldown() async {
        let context = PresenceContext(minutesUntilNextMeeting: 5, nextEventTitle: "X")
        let busy = makeLoop(context: context, rules: [MeetingPrepRule()], canSurface: false)
        let outcome = await busy.evaluate()
        XCTAssertEqual(outcome, .idle)
        // The store must NOT have marked a fire — a later evaluation still runs.
        let free = makeLoop(context: context, rules: [MeetingPrepRule()])
        let second = await free.evaluate()
        if case .acted = second {} else { XCTFail("expected acted after deferral") }
    }

    func testCooldownPreventsImmediateRefire() async {
        let context = PresenceContext(minutesUntilNextMeeting: 5, nextEventTitle: "X")
        let loop = makeLoop(context: context, rules: [MeetingPrepRule()])
        _ = await loop.evaluate()
        let second = await loop.evaluate()
        XCTAssertEqual(second, .idle)
    }

    func testQuietHoursHoldEverythingExceptMeetingPrep() async {
        let quiet = ProactiveSettings(enabled: true, sourceEnabled: [:],
                                      quietHoursEnabled: true,
                                      quietHours: QuietHours(startHour: 0, endHour: 24))
        // Inbox triage held.
        var outcome = await makeLoop(context: PresenceContext(newUnreadMail: 3),
                                     rules: [InboxTriageRule()], proactive: quiet).evaluate()
        XCTAssertEqual(outcome, .idle)
        // Meeting prep bypasses.
        outcome = await makeLoop(
            context: PresenceContext(minutesUntilNextMeeting: 5, nextEventTitle: "X"),
            rules: [MeetingPrepRule()], proactive: quiet).evaluate()
        if case .acted = outcome {} else { XCTFail("meeting prep should bypass quiet hours") }
    }

    func testDailyBriefMarksDayStamp() async {
        let loop = makeLoop(context: PresenceContext(hour: 8, dailyBriefAlreadyRanToday: false),
                            rules: [DailyBriefRule()])
        let outcome = await loop.evaluate()
        if case .acted(let id, _) = outcome {
            XCTAssertEqual(id, PlaybookLibrary.dailyBrief)
        } else {
            XCTFail("expected daily brief to act")
        }
        XCTAssertTrue(LiveLoopStore(defaults: defaults).briefAlreadyRan(on: Date()))
    }

    func testRankerPicksMeetingPrepOverTriage() async {
        let acted = Recorder()
        let context = PresenceContext(minutesUntilNextMeeting: 3, nextEventTitle: "Demo",
                                      newUnreadMail: 2)
        let loop = makeLoop(context: context,
                            rules: [InboxTriageRule(), MeetingPrepRule()], acted: acted)
        let outcome = await loop.evaluate()
        if case .acted(let id, _) = outcome {
            XCTAssertEqual(id, PlaybookLibrary.meetingPrep)
        } else {
            XCTFail("expected meeting prep to win ranking")
        }
    }
}

/// Async-safe line recorder for observing loop callbacks.
actor Recorder {
    private(set) var lines: [String] = []
    func append(_ line: String) { lines.append(line) }
}
