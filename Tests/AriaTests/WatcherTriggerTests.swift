import XCTest
@testable import Aria

/// V11 P7 — watcher triggers: mail matches and web page changes, built as a
/// precheck state machine (prime → unchanged → fired) so watchers stay quiet
/// until something genuinely happened.
final class WatcherTriggerTests: XCTestCase {

    private func day(_ d: Int, hour: Int = 10, minute: Int = 0) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = d
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    // MARK: due-time math

    func testMailTriggerDueOnItsPollInterval() {
        let t = AgentTrigger.mailMatched(query: "investor")
        XCTAssertTrue(AgentSchedule.isDue(t, now: day(11), lastRun: nil))
        XCTAssertFalse(AgentSchedule.isDue(t, now: day(11, hour: 10, minute: 2),
                                           lastRun: day(11)))
        XCTAssertTrue(AgentSchedule.isDue(t, now: day(11, hour: 10, minute: 6),
                                          lastRun: day(11)))
    }

    func testURLTriggerDueOnItsPollInterval() {
        let t = AgentTrigger.urlChanged(url: "https://example.com")
        XCTAssertTrue(AgentSchedule.isDue(t, now: day(11), lastRun: nil))
        XCTAssertFalse(AgentSchedule.isDue(t, now: day(11, hour: 10, minute: 20),
                                           lastRun: day(11)))
        XCTAssertTrue(AgentSchedule.isDue(t, now: day(11, hour: 10, minute: 31),
                                          lastRun: day(11)))
    }

    // MARK: precheck state machine

    func testFirstObservationPrimesQuietly() {
        let outcome = WatcherCheck.evaluate(current: "subject A", watermark: nil)
        guard case .primed(let wm) = outcome else { return XCTFail("expected primed") }
        XCTAssertEqual(wm, WatcherCheck.hash("subject A"))
    }

    func testUnchangedContentStaysQuiet() {
        let wm = WatcherCheck.hash("subject A")
        XCTAssertEqual(WatcherCheck.evaluate(current: "subject A", watermark: wm), .unchanged)
    }

    func testChangedContentFiresWithContext() {
        let wm = WatcherCheck.hash("subject A")
        let outcome = WatcherCheck.evaluate(current: "subject A\nsubject B", watermark: wm)
        guard case .fired(let context, let newWM) = outcome else { return XCTFail("expected fired") }
        XCTAssertTrue(context.contains("subject B"))
        XCTAssertEqual(newWM, WatcherCheck.hash("subject A\nsubject B"))
    }

    func testUnavailableSourceNeverFires() {
        XCTAssertEqual(WatcherCheck.evaluate(current: nil, watermark: "anything"), .unavailable)
        XCTAssertEqual(WatcherCheck.evaluate(current: nil, watermark: nil), .unavailable)
    }

    func testHashIsStableAndDistinct() {
        XCTAssertEqual(WatcherCheck.hash("x"), WatcherCheck.hash("x"))
        XCTAssertNotEqual(WatcherCheck.hash("x"), WatcherCheck.hash("y"))
    }

    // MARK: persistence

    func testWatcherAgentRoundTripsWithWatermark() throws {
        var agent = BackgroundAgent(name: "Investor mail",
                                    goal: "Notify me about investor emails",
                                    trigger: .mailMatched(query: "investor"))
        agent.watermark = "abc123"
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(BackgroundAgent.self, from: encoder.encode(agent))
        XCTAssertEqual(decoded, agent)
    }

    func testLegacyAgentJSONStillDecodes() throws {
        // Pre-V11 agents.json had no watermark and only the original triggers.
        let legacy = #"{"id":"00000000-0000-0000-0000-000000000001","name":"x","goal":"g","trigger":{"daily":{"hour":9,"minute":0}},"enabled":true}"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let agent = try decoder.decode(BackgroundAgent.self, from: Data(legacy.utf8))
        XCTAssertEqual(agent.name, "x")
        XCTAssertNil(agent.watermark)
    }

    func testTouchUpdatesWatermarkWithoutRunHistory() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agents-\(UUID().uuidString).json")
        let store = AgentStore(fileURL: url)
        let agent = BackgroundAgent(name: "w", goal: "g",
                                    trigger: .urlChanged(url: "https://example.com"))
        await store.upsert(agent)
        await store.touch(agent.id, at: day(11), watermark: "wm1")
        let stored = await store.all().first
        XCTAssertEqual(stored?.watermark, "wm1")
        XCTAssertEqual(stored?.lastRun, day(11))
        let runs = await store.recentRuns(10)
        XCTAssertTrue(runs.isEmpty, "quiet skips must not appear in run history")
    }
}
