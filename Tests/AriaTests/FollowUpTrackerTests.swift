import XCTest
@testable import Aria

final class FollowUpTrackerTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-followups-\(UUID().uuidString).json")
    }

    func testTrackAddsFollowUp() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let tracker = FollowUpTracker(fileURL: url)
        await tracker.track(subject: "Project proposal", recipient: "alice@co.com")
        let all = await tracker.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].subject, "Project proposal")
        XCTAssertEqual(all[0].recipient, "alice@co.com")
        XCTAssertFalse(all[0].resolved)
    }

    func testOverdueFiltersCorrectly() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let tracker = FollowUpTracker(fileURL: url)

        // Overdue: sent 3 days ago, expected reply within 2 days
        let threeDaysAgo = Date().addingTimeInterval(-3 * 86400)
        let oneDayAgo = Date().addingTimeInterval(-1 * 86400)

        // Manually inject via track but with custom sent dates — we'll use a helper
        // Since track() uses Date(), we test via all() + overdue logic
        // We create via track and then check:
        // Simulate by creating PendingFollowUp directly if we can access internals —
        // but since we can only call track(), we test with 0 expectedWithin for immediate overdue

        await tracker.track(subject: "Overdue email", recipient: "bob@co.com", expectedWithin: 0)
        await tracker.track(subject: "Not yet due", recipient: "carol@co.com", expectedWithin: 86400 * 7)

        let now = Date().addingTimeInterval(1)  // 1 second later
        let overdue = await tracker.overdue(now: now)
        XCTAssertEqual(overdue.count, 1)
        XCTAssertEqual(overdue[0].subject, "Overdue email")
    }

    func testResolveMarksResolved() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let tracker = FollowUpTracker(fileURL: url)
        await tracker.track(subject: "Need reply", recipient: "dave@co.com", expectedWithin: 0)
        let all = await tracker.all()
        let id = all[0].id
        await tracker.resolve(id)
        let updated = await tracker.all()
        XCTAssertTrue(updated[0].resolved)

        // Should not appear in overdue
        let overdue = await tracker.overdue(now: Date().addingTimeInterval(1))
        XCTAssertTrue(overdue.isEmpty)
    }

    func testSnoozePostponesItem() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let tracker = FollowUpTracker(fileURL: url)
        await tracker.track(subject: "Snoozed item", recipient: "eve@co.com", expectedWithin: 0)
        let all = await tracker.all()
        let id = all[0].id

        // Snooze for 1 hour
        await tracker.snooze(id, for: 3600)

        // Right now → not overdue (snoozed)
        let overdueNow = await tracker.overdue(now: Date().addingTimeInterval(1))
        XCTAssertTrue(overdueNow.isEmpty)

        // 2 hours from now → overdue again
        let overdueAfter = await tracker.overdue(now: Date().addingTimeInterval(7200))
        XCTAssertEqual(overdueAfter.count, 1)
    }

    func testOverdueRespectsSnoozedUntil() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let tracker = FollowUpTracker(fileURL: url)
        await tracker.track(subject: "Test", recipient: "x@co.com", expectedWithin: 0)
        let all = await tracker.all()
        let id = all[0].id

        // Snooze for 2 hours
        await tracker.snooze(id, for: 7200)

        // 1 hour from now → still snoozed
        let afterOneHour = await tracker.overdue(now: Date().addingTimeInterval(3600))
        XCTAssertTrue(afterOneHour.isEmpty)

        // 3 hours from now → overdue
        let afterThreeHours = await tracker.overdue(now: Date().addingTimeInterval(3 * 3600))
        XCTAssertEqual(afterThreeHours.count, 1)
    }

    func testPersistenceRoundtrip() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let tracker1 = FollowUpTracker(fileURL: url)
        await tracker1.track(subject: "Persisted follow-up", recipient: "frank@co.com")
        let all1 = await tracker1.all()
        XCTAssertEqual(all1.count, 1)

        // Create a new tracker from same URL
        let tracker2 = FollowUpTracker(fileURL: url)
        let all2 = await tracker2.all()
        XCTAssertEqual(all2.count, 1)
        XCTAssertEqual(all2[0].subject, "Persisted follow-up")
        XCTAssertEqual(all2[0].recipient, "frank@co.com")
    }

    func testMultipleTrackedItems() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let tracker = FollowUpTracker(fileURL: url)
        await tracker.track(subject: "Email 1", recipient: "a@co.com")
        await tracker.track(subject: "Email 2", recipient: "b@co.com")
        await tracker.track(subject: "Email 3", recipient: "c@co.com")
        let all = await tracker.all()
        XCTAssertEqual(all.count, 3)
    }
}
