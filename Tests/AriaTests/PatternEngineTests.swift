import XCTest
@testable import Aria

final class PatternEngineTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-\(name)-\(UUID().uuidString).json")
    }

    private func makeEngine(observationStart: Date) async -> PatternEngine {
        let logURL = tempURL("obs")
        // Seed an observation store with a back-dated startedAt so the 14-day
        // grace period is satisfied.
        var store = ObservationStore()
        store.startedAt = observationStart
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(store).write(to: logURL)
        let log = ObservationLog(fileURL: logURL)
        return PatternEngine(log: log, fileURL: tempURL("patterns"))
    }

    func testObservationGraceBlocksSuggestions() async {
        let engine = await makeEngine(observationStart: Date())  // day 0
        // Even with strong data, no suggestions before 14 days.
        for _ in 0..<6 { await engine.recordCommand("clear downloads") }
        _ = await engine.analyzePatterns(sensitivity: 0.7)
        let suggestions = await engine.patternsToSuggest()
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testSuggestsAfterGracePeriod() async {
        let start = Date(timeIntervalSinceNow: -20 * 24 * 3600)  // 20 days ago
        let engine = await makeEngine(observationStart: start)
        // 6 occurrences ~same time today.
        let base = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
        for i in 0..<6 {
            await engine.recordCommand("standup notes", at: base.addingTimeInterval(Double(i) * 120))
        }
        _ = await engine.analyzePatterns(sensitivity: 0.7)
        let suggestions = await engine.patternsToSuggest()
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertEqual(suggestions.first?.status, .observing)  // returned pre-mutation snapshot
    }

    func testApproveAndSuppressLifecycle() async {
        let start = Date(timeIntervalSinceNow: -20 * 24 * 3600)
        let engine = await makeEngine(observationStart: start)
        let base = Calendar.current.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        for i in 0..<6 { await engine.recordCommand("git pull", at: base.addingTimeInterval(Double(i) * 60)) }
        _ = await engine.analyzePatterns(sensitivity: 0.7)
        guard let p = await engine.allPatterns().first else { return XCTFail("no pattern") }

        await engine.approve(p.id, mode: .auto)
        let approvedStatus = await engine.allPatterns().first?.status
        XCTAssertEqual(approvedStatus, .approved)

        await engine.suppress(p.id)
        let suppressedStatus = await engine.allPatterns().first?.status
        XCTAssertEqual(suppressedStatus, .suppressed)
    }

    func testForgetEverythingWipes() async {
        let engine = await makeEngine(observationStart: Date(timeIntervalSinceNow: -20 * 24 * 3600))
        for _ in 0..<6 { await engine.recordCommand("task x") }
        _ = await engine.analyzePatterns(sensitivity: 0.7)
        let before = await engine.allPatterns()
        XCTAssertFalse(before.isEmpty)
        await engine.forgetEverything()
        let after = await engine.allPatterns()
        XCTAssertTrue(after.isEmpty)
    }

    func testObservationPruningKeepsRecent() async {
        let log = ObservationLog(fileURL: tempURL("obs2"))
        await log.recordCommand("old", at: Date(timeIntervalSinceNow: -100 * 24 * 3600))
        await log.recordCommand("new", at: Date())
        let commands = await log.store.commands
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.command, "new")
    }

    func testLearningSettingsDefaults() {
        let suite = UserDefaults(suiteName: "aria-brain-\(UUID().uuidString)")!
        let s = LearningSettings.load(suite)
        XCTAssertTrue(s.enabled)
        XCTAssertFalse(s.automationsPaused)
        XCTAssertEqual(s.sensitivity, 0.75, accuracy: 0.001)
    }
}
