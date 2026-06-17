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

    // MARK: Self-improvement loop (P12) — outcome-gated automation firing

    /// Build an approved time-of-day pattern that matches `fire`, via the real
    /// detection pipeline (mirrors testApproveAndSuppressLifecycle).
    private func makeApprovedPattern(fire: Date) async -> (PatternEngine, UUID) {
        let engine = await makeEngine(observationStart: fire.addingTimeInterval(-20 * 24 * 3600))
        for i in 0..<6 {
            await engine.recordCommand("deploy site", at: fire.addingTimeInterval(Double(i) * 60))
        }
        _ = await engine.analyzePatterns(sensitivity: 0.7)
        guard let p = await engine.allPatterns().first else {
            XCTFail("no pattern detected"); return (engine, UUID())
        }
        await engine.approve(p.id, mode: .auto)
        return (engine, p.id)
    }

    func testFailingAutomationStopsFiring() async {
        let fire = Calendar.current.startOfDay(for: Date()).addingTimeInterval(10 * 3600)
        let (engine, id) = await makeApprovedPattern(fire: fire)
        // It fires while its track record is clean.
        let firstRun = await engine.automationsToFire(now: fire)
        XCTAssertEqual(firstRun.count, 1)
        // Three consecutive failures push success ratio below 50%.
        for _ in 0..<3 { await engine.recordOutcome(id, success: false) }
        // Next eligible window (past the refire interval): it must NOT fire.
        let later = fire.addingTimeInterval(7 * 24 * 3600)  // same weekday+time, past refire interval
        let secondRun = await engine.automationsToFire(now: later)
        XCTAssertTrue(secondRun.isEmpty, "a repeatedly-failing automation should stop firing")
    }

    func testHealthyAutomationKeepsFiring() async {
        let fire = Calendar.current.startOfDay(for: Date()).addingTimeInterval(10 * 3600)
        let (engine, id) = await makeApprovedPattern(fire: fire)
        for _ in 0..<3 { await engine.recordOutcome(id, success: true) }
        let later = fire.addingTimeInterval(7 * 24 * 3600)  // same weekday+time, past refire interval
        let run = await engine.automationsToFire(now: later)
        XCTAssertEqual(run.count, 1, "a succeeding automation should keep firing")
    }

    func testRecordOutcomeTracksSuccessRatio() async {
        let fire = Calendar.current.startOfDay(for: Date()).addingTimeInterval(10 * 3600)
        let (engine, id) = await makeApprovedPattern(fire: fire)
        await engine.recordOutcome(id, success: true)
        await engine.recordOutcome(id, success: false)
        let p = await engine.allPatterns().first { $0.id == id }
        XCTAssertEqual(p?.fireCount, 2)
        XCTAssertEqual(p?.successCount, 1)
        XCTAssertEqual(p?.successRatio ?? 0, 0.5, accuracy: 0.001)
    }

    func testUnprovenAutomationFiresOptimistically() async {
        // Fewer than the sample threshold of failures: don't pre-emptively block.
        let fire = Calendar.current.startOfDay(for: Date()).addingTimeInterval(10 * 3600)
        let (engine, id) = await makeApprovedPattern(fire: fire)
        await engine.recordOutcome(id, success: false)  // 1 sample only
        let later = fire.addingTimeInterval(7 * 24 * 3600)  // same weekday+time, past refire interval
        let run = await engine.automationsToFire(now: later)
        XCTAssertEqual(run.count, 1, "below the sample threshold, fire optimistically")
    }

    func testLearningSettingsDefaults() {
        let suite = UserDefaults(suiteName: "aria-brain-\(UUID().uuidString)")!
        let s = LearningSettings.load(suite)
        XCTAssertTrue(s.enabled)
        XCTAssertFalse(s.automationsPaused)
        XCTAssertEqual(s.sensitivity, 0.75, accuracy: 0.001)
    }
}
