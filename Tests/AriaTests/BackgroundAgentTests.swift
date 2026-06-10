import XCTest
@testable import Aria

final class AgentScheduleTests: XCTestCase {

    private func date(_ h: Int, _ m: Int, day: Int = 10) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = day; c.hour = h; c.minute = m
        return Calendar.current.date(from: c)!
    }

    func testDailyTriggerDueAtOrAfterTime() {
        let trigger = AgentTrigger.daily(hour: 9, minute: 0)
        // Not yet run today, now 9:05 → due.
        XCTAssertTrue(AgentSchedule.isDue(trigger, now: date(9, 5), lastRun: nil))
        // Already ran today → not due again.
        XCTAssertFalse(AgentSchedule.isDue(trigger, now: date(9, 5), lastRun: date(9, 1)))
        // Before the time → not due.
        XCTAssertFalse(AgentSchedule.isDue(trigger, now: date(8, 59), lastRun: nil))
        // Ran yesterday, now past time today → due.
        XCTAssertTrue(AgentSchedule.isDue(trigger, now: date(9, 5), lastRun: date(9, 1, day: 9)))
    }

    func testIntervalTriggerDueAfterElapsed() {
        let trigger = AgentTrigger.interval(seconds: 3600)
        XCTAssertTrue(AgentSchedule.isDue(trigger, now: date(10, 0), lastRun: nil), "never ran → due")
        XCTAssertFalse(AgentSchedule.isDue(trigger, now: date(10, 0), lastRun: date(9, 30)))
        XCTAssertTrue(AgentSchedule.isDue(trigger, now: date(10, 31), lastRun: date(9, 30)))
    }

    func testFolderTriggerNeverTimerDue() {
        // Folder triggers fire from the watcher, not the timer sweep.
        XCTAssertFalse(AgentSchedule.isDue(.folderChanged(path: "/tmp"), now: date(12, 0), lastRun: nil))
    }
}

final class AgentStoreTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agents-\(UUID().uuidString).json")
    }

    private func briefing() -> BackgroundAgent {
        BackgroundAgent(name: "Daily briefing",
                        goal: "Summarize today's calendar and recent email into a short briefing note",
                        trigger: .daily(hour: 9, minute: 0))
    }

    func testCRUDAndPersistence() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AgentStore(fileURL: url)
        let agent = briefing()
        await store.upsert(agent)
        var all = await store.all()
        XCTAssertEqual(all.count, 1)

        var updated = agent
        updated.enabled = false
        await store.upsert(updated)
        all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertFalse(all[0].enabled)

        // Persists across instances.
        let store2 = AgentStore(fileURL: url)
        let reloaded = await store2.all()
        XCTAssertEqual(reloaded.first?.name, "Daily briefing")

        await store2.remove(agent.id)
        let empty = await store2.all()
        XCTAssertTrue(empty.isEmpty)
    }

    func testMarkRunRecordsOutcomeAndHistory() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AgentStore(fileURL: url)
        let agent = briefing()
        await store.upsert(agent)
        await store.markRun(agent.id, at: Date(timeIntervalSince1970: 1000), ok: true, summary: "Briefing saved.")
        let all = await store.all()
        XCTAssertEqual(all[0].lastRun, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(all[0].lastOutcome, "Briefing saved.")
        let runs = await store.recentRuns(10)
        XCTAssertEqual(runs.count, 1)
        XCTAssertTrue(runs[0].ok)
    }

    func testSurvivesCorruptFile() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try? Data("][".utf8).write(to: url)
        let store = AgentStore(fileURL: url)
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testDueAgentsFiltersEnabledAndDue() async {
        let store = AgentStore(fileURL: tempURL())
        var a = briefing()                       // daily 9:00
        var b = BackgroundAgent(name: "hourly", goal: "g", trigger: .interval(seconds: 3600))
        b.enabled = false                        // disabled → never due
        await store.upsert(a)
        await store.upsert(b)
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 10; c.hour = 9; c.minute = 30
        let now = Calendar.current.date(from: c)!
        let due = await store.dueAgents(now: now)
        XCTAssertEqual(due.map(\.name), ["Daily briefing"])
        _ = a; _ = b
    }
}
