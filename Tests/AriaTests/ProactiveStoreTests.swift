import XCTest
@testable import Aria

final class ProactiveStoreTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testSuppressedAfterThreeConsecutiveDismissals() {
        var store = ProactiveStore()
        let key = "routine:abc"
        XCTAssertFalse(store.isSuppressed(key: key, now: t0))
        store.record(.dismissed, key: key, now: t0)
        store.record(.dismissed, key: key, now: t0.addingTimeInterval(60))
        XCTAssertFalse(store.isSuppressed(key: key, now: t0.addingTimeInterval(120)))
        store.record(.dismissed, key: key, now: t0.addingTimeInterval(120))
        XCTAssertTrue(store.isSuppressed(key: key, now: t0.addingTimeInterval(180)))
    }

    func testAcceptResetsSuppression() {
        var store = ProactiveStore()
        let key = "routine:abc"
        for i in 0..<3 { store.record(.dismissed, key: key, now: t0.addingTimeInterval(Double(i))) }
        XCTAssertTrue(store.isSuppressed(key: key, now: t0))
        store.record(.accepted, key: key, now: t0.addingTimeInterval(10))
        XCTAssertFalse(store.isSuppressed(key: key, now: t0.addingTimeInterval(11)))
    }

    func testSuppressionDecaysAfterWindow() {
        var store = ProactiveStore()
        let key = "routine:abc"
        for i in 0..<3 { store.record(.dismissed, key: key, now: t0.addingTimeInterval(Double(i))) }
        XCTAssertTrue(store.isSuppressed(key: key, now: t0))
        // 15 days later the suppression has decayed
        let later = t0.addingTimeInterval(15 * 24 * 3600)
        XCTAssertFalse(store.isSuppressed(key: key, now: later))
    }

    func testExpiredOutcomeDoesNotCountAsDismissal() {
        var store = ProactiveStore()
        let key = "calendar:evt"
        for i in 0..<5 { store.record(.expired, key: key, now: t0.addingTimeInterval(Double(i))) }
        XCTAssertFalse(store.isSuppressed(key: key, now: t0))
    }

    func testPersistenceRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("proactive-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var store = ProactiveStore()
        for i in 0..<3 { store.record(.dismissed, key: "k", now: t0.addingTimeInterval(Double(i))) }
        ProactiveStoreFile.save(store, to: url)
        let loaded = ProactiveStoreFile.load(from: url)
        XCTAssertTrue(loaded.isSuppressed(key: "k", now: t0))
    }
}
