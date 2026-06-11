import XCTest
@testable import Aria

/// V11 P6 — Aria Timeline: one merged, chronological view over the stores that
/// already capture work (WorkJournal, ActivityLog). Aggregation only — the
/// timeline owns no persistence of its own.
final class TimelineTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).json")
    }

    private func day(_ d: Int, hour: Int = 10) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = d; c.hour = hour
        return Calendar.current.date(from: c)!
    }

    private func makeStores() -> (WorkJournal, ActivityLog) {
        (WorkJournal(fileURL: tempURL("journal")), ActivityLog(url: tempURL("activity")))
    }

    func testMergesJournalAndActivityChronologically() async {
        let (journal, activity) = makeStores()
        await journal.record(kind: .task, title: "organize downloads", outcome: "12 sorted", ok: true, at: day(10, hour: 9))
        await activity.record(tool: "save_note", detail: "mic picks", result: .ok("Saved"), at: day(10, hour: 11))
        await journal.record(kind: .agent, title: "Daily briefing", outcome: "delivered", ok: true, at: day(10, hour: 8))

        let timeline = Timeline(journal: journal, activity: activity)
        let events = await timeline.events(from: day(10, hour: 0), to: day(11, hour: 0))
        XCTAssertEqual(events.map(\.title), ["Daily briefing", "organize downloads", "mic picks"])
        XCTAssertEqual(events.map(\.source), [.agent, .task, .action])
    }

    func testEventsCarryProjectTags() async {
        let (journal, activity) = makeStores()
        await journal.record(kind: .task, title: "deck", outcome: "", ok: true, project: "Verdai", at: day(10))
        let timeline = Timeline(journal: journal, activity: activity)
        let events = await timeline.events(from: day(10, hour: 0), to: day(11, hour: 0))
        XCTAssertEqual(events.first?.project, "Verdai")
    }

    func testDayRollupGroupsByDayWithCounts() async {
        let (journal, activity) = makeStores()
        await journal.record(kind: .task, title: "a", outcome: "", ok: true, at: day(9, hour: 9))
        await journal.record(kind: .task, title: "b", outcome: "", ok: false, at: day(9, hour: 10))
        await journal.record(kind: .task, title: "c", outcome: "", ok: true, at: day(10, hour: 9))

        let timeline = Timeline(journal: journal, activity: activity)
        let rollup = await timeline.dayRollup(from: day(9, hour: 0), to: day(11, hour: 0))
        // Two day headers, counts on each.
        XCTAssertTrue(rollup.contains("Jun 9"))
        XCTAssertTrue(rollup.contains("Jun 10"))
        XCTAssertTrue(rollup.contains("1 done, 1 failed"))
    }

    func testEmptyWindowReadsEmpty() async {
        let (journal, activity) = makeStores()
        let timeline = Timeline(journal: journal, activity: activity)
        let events = await timeline.events(from: day(1, hour: 0), to: day(2, hour: 0))
        XCTAssertTrue(events.isEmpty)
        let rollup = await timeline.dayRollup(from: day(1, hour: 0), to: day(2, hour: 0))
        XCTAssertTrue(rollup.isEmpty)
    }

    func testActivityLogRangeQuery() async {
        let activity = ActivityLog(url: tempURL("activity"))
        await activity.record(tool: "shell", detail: "ls", result: .ok("ok"), at: day(9))
        await activity.record(tool: "shell", detail: "pwd", result: .ok("ok"), at: day(11))
        let window = await activity.entries(from: day(10, hour: 0), to: day(12, hour: 0))
        XCTAssertEqual(window.map(\.detail), ["pwd"])
    }

    // MARK: tool

    func testTimelineToolAnswersToday() async throws {
        let (journal, activity) = makeStores()
        await journal.record(kind: .task, title: "organize downloads", outcome: "12 sorted", ok: true, at: day(10, hour: 9))
        let tool = TimelineTool(timeline: Timeline(journal: journal, activity: activity),
                                now: { self.day(10, hour: 18) })
        let result = try await tool.run(input: ["timeframe": "today"])
        XCTAssertTrue(result.output.contains("organize downloads"))
    }

    func testTimelineToolWeekUsesRollup() async throws {
        let (journal, activity) = makeStores()
        await journal.record(kind: .task, title: "a", outcome: "", ok: true, at: day(8, hour: 9))
        await journal.record(kind: .task, title: "b", outcome: "", ok: true, at: day(10, hour: 9))
        let tool = TimelineTool(timeline: Timeline(journal: journal, activity: activity),
                                now: { self.day(10, hour: 18) })
        let result = try await tool.run(input: ["timeframe": "this week"])
        XCTAssertTrue(result.output.contains("Jun 8"))
        XCTAssertTrue(result.output.contains("Jun 10"))
    }
}
