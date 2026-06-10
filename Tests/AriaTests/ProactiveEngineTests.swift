import XCTest
@testable import Aria

private struct FakeProvider: SignalProvider {
    let source: SuggestionSource
    let items: [Suggestion]
    func candidates(now: Date) async -> [Suggestion] { items }
}

final class ProactiveEngineTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-\(UUID().uuidString).json")
    }

    private func settings(enabled: Bool = true,
                          calendar: Bool = true,
                          routine: Bool = true,
                          quiet: Bool = false) -> ProactiveSettings {
        ProactiveSettings(
            enabled: enabled,
            sourceEnabled: [.calendar: calendar, .routine: routine, .command: true, .screen: false],
            quietHoursEnabled: quiet,
            quietHours: QuietHours(startHour: 0, endHour: 23))
    }

    private func sugg(_ key: String,
                      source: SuggestionSource = .routine,
                      urgency: Urgency = .ambient,
                      confidence: Double = 0.7,
                      expiry: Date? = nil) -> Suggestion {
        Suggestion(source: source, spokenLine: key, action: .acknowledge,
                   confidence: confidence, urgency: urgency,
                   createdAt: now, expiry: expiry ?? now.addingTimeInterval(600),
                   dedupeKey: key)
    }

    func testReturnsNilWhenDisabled() async {
        let engine = ProactiveEngine(
            providers: [FakeProvider(source: .routine, items: [sugg("a")])],
            settings: { self.settings(enabled: false) },
            storeURL: tempURL())
        let out = await engine.tick(now: now)
        XCTAssertNil(out)
    }

    func testPicksTimeCriticalOverAmbient() async {
        let engine = ProactiveEngine(
            providers: [
                FakeProvider(source: .routine, items: [sugg("ambient", confidence: 0.95)]),
                FakeProvider(source: .calendar, items: [sugg("crit", source: .calendar, urgency: .timeCritical, confidence: 0.5)])
            ],
            settings: { self.settings() },
            storeURL: tempURL())
        let out = await engine.tick(now: now)
        XCTAssertEqual(out?.dedupeKey, "crit")
    }

    func testFiltersExpired() async {
        let engine = ProactiveEngine(
            providers: [FakeProvider(source: .routine, items: [sugg("old", expiry: now.addingTimeInterval(-1))])],
            settings: { self.settings() },
            storeURL: tempURL())
        let out = await engine.tick(now: now)
        XCTAssertNil(out)
    }

    func testFiltersDisabledSource() async {
        let engine = ProactiveEngine(
            providers: [FakeProvider(source: .calendar, items: [sugg("c", source: .calendar)])],
            settings: { self.settings(calendar: false) },
            storeURL: tempURL())
        let out = await engine.tick(now: now)
        XCTAssertNil(out)
    }

    func testSuppressedAfterDismissals() async {
        let engine = ProactiveEngine(
            providers: [FakeProvider(source: .routine, items: [sugg("a")])],
            settings: { self.settings() },
            storeURL: tempURL())
        let s = sugg("a")
        await engine.record(.dismissed, for: s, now: now)
        await engine.record(.dismissed, for: s, now: now)
        await engine.record(.dismissed, for: s, now: now)
        let out = await engine.tick(now: now)
        XCTAssertNil(out)
    }

    func testQuietHoursAllowsOnlyTimeCritical() async {
        let engine = ProactiveEngine(
            providers: [
                FakeProvider(source: .routine, items: [sugg("ambient")]),
                FakeProvider(source: .calendar, items: [sugg("crit", source: .calendar, urgency: .timeCritical)])
            ],
            settings: { self.settings(quiet: true) },
            storeURL: tempURL())
        let out = await engine.tick(now: now)
        XCTAssertEqual(out?.dedupeKey, "crit")
    }

    func testDedupesByKey() async {
        let engine = ProactiveEngine(
            providers: [
                FakeProvider(source: .routine, items: [sugg("dup", confidence: 0.4)]),
                FakeProvider(source: .routine, items: [sugg("dup", confidence: 0.9)])
            ],
            settings: { self.settings() },
            storeURL: tempURL())
        let out = await engine.tick(now: now)
        XCTAssertEqual(out?.dedupeKey, "dup")
        XCTAssertEqual(out?.confidence, 0.9)   // kept the higher-confidence copy
    }

    func testRecordPersistsSuppression() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = ProactiveEngine(
            providers: [FakeProvider(source: .routine, items: [sugg("a")])],
            settings: { self.settings() },
            storeURL: url)
        let s = sugg("a")
        for _ in 0..<3 { await engine.record(.dismissed, for: s, now: now) }
        // a fresh engine reading the same file should see the suppression
        let engine2 = ProactiveEngine(
            providers: [FakeProvider(source: .routine, items: [sugg("a")])],
            settings: { self.settings() },
            storeURL: url)
        let out = await engine2.tick(now: now)
        XCTAssertNil(out)
    }
}
