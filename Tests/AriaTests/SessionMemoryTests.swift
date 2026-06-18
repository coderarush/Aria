import XCTest
@testable import Aria

final class SessionMemoryTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-session-\(UUID().uuidString).json")
    }

    func testRecordAndRecallLatest() async {
        let store = SessionMemoryStore(fileURL: tempURL())
        await store.record(SessionSnapshot(project: "Aria", goal: "ship v12",
                                           progress: "levers done", nextStep: "wire ContextCoordinator"))
        let latest = await store.latest()
        XCTAssertEqual(latest?.goal, "ship v12")
        XCTAssertEqual(latest?.nextStep, "wire ContextCoordinator")
    }

    func testLatestFiltersByProject() async {
        let store = SessionMemoryStore(fileURL: tempURL())
        let t = Date()
        await store.record(SessionSnapshot(project: "Aria", goal: "A", date: t))
        await store.record(SessionSnapshot(project: "Website", goal: "W", date: t.addingTimeInterval(10)))
        let aria = await store.latest(project: "aria")   // case-insensitive
        XCTAssertEqual(aria?.goal, "A")
        let overall = await store.latest()                // newest across projects
        XCTAssertEqual(overall?.goal, "W")
    }

    func testExpiredSnapshotsPrunedOnRecord() async {
        let store = SessionMemoryStore(fileURL: tempURL())
        let now = Date()
        // 20 days old with a 14-day ttl → already expired.
        await store.record(SessionSnapshot(project: "Old", goal: "stale",
                                           date: now.addingTimeInterval(-20 * 86400), ttlDays: 14),
                           now: now)
        await store.record(SessionSnapshot(project: "New", goal: "fresh", date: now), now: now)
        let active = await store.active(now: now)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.goal, "fresh")
        let stale = await store.latest(project: "Old", now: now)
        XCTAssertNil(stale)
    }

    func testDefaultExpiryIsInFuture() {
        let snap = SessionSnapshot(project: nil, goal: "g")
        XCTAssertGreaterThan(snap.expiresAt, snap.date)
    }
}
