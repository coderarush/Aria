import XCTest
@testable import Aria

final class ActivityLogTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-activity-\(UUID().uuidString)/activity.json")
    }

    func testOutcomeMappingKeepsDeclineDistinctFromFailure() {
        XCTAssertEqual(ActivityEntry.outcome(for: .ok("done")), .ok)
        XCTAssertEqual(ActivityEntry.outcome(for: .cancelled()), .declined)
        XCTAssertEqual(ActivityEntry.outcome(for: .fail("disk full")), .failed)
    }

    func testTidyCollapsesNewlinesAndCaps() {
        XCTAssertEqual(ActivityEntry.tidy("a\nb\nc"), "a b c")
        let long = String(repeating: "x", count: 500)
        let tidied = ActivityEntry.tidy(long, max: 140)
        XCTAssertEqual(tidied.count, 141)            // 140 + the ellipsis
        XCTAssertTrue(tidied.hasSuffix("…"))
    }

    func testTrimmedKeepsLastCapEntries() {
        let made = (0..<10).map {
            ActivityEntry(tool: "t\($0)", detail: "", outcome: .ok, summary: "")
        }
        let kept = ActivityLog.trimmed(made, cap: 3)
        XCTAssertEqual(kept.map(\.tool), ["t7", "t8", "t9"])
        XCTAssertEqual(ActivityLog.trimmed(made, cap: 50).count, 10)   // under cap: unchanged
    }

    func testRecordPersistsAndRecentIsNewestFirst() async throws {
        let url = tempURL()
        let log = ActivityLog(url: url, cap: 100)
        await log.record(tool: "open_app", detail: "name=Safari", result: .ok("opened"))
        await log.record(tool: "send_mail", detail: "to=x", result: .cancelled())

        let recent = await log.recent()
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent.first?.tool, "send_mail")      // newest first
        XCTAssertEqual(recent.first?.outcome, .declined)
        XCTAssertEqual(recent.last?.outcome, .ok)

        // Survives a fresh instance pointed at the same file (durable/traceable).
        let reopened = ActivityLog(url: url, cap: 100)
        let after = await reopened.recent()
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after.first?.tool, "send_mail")
    }

    func testCapEvictsOldestOnRecord() async {
        let log = ActivityLog(url: tempURL(), cap: 3)
        for i in 0..<5 { await log.record(tool: "t\(i)", detail: "", result: .ok("")) }
        let recent = await log.recent()
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent.map(\.tool), ["t4", "t3", "t2"])   // newest first, oldest evicted
    }
}
