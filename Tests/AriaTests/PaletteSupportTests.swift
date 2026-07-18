import XCTest
@testable import Aria

final class RecentCommandsTests: XCTestCase {

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "rc-\(UUID().uuidString)")! }

    func testRecordsNewestFirstAndDedupes() {
        let d = defaults()
        RecentCommands.record("open safari", defaults: d)
        RecentCommands.record("summarize this", defaults: d)
        RecentCommands.record("open safari", defaults: d)   // re-run → moves to front
        XCTAssertEqual(RecentCommands.all(defaults: d), ["open safari", "summarize this"])
    }

    func testCapsAtEight() {
        let d = defaults()
        for i in 0..<12 { RecentCommands.record("cmd \(i)", defaults: d) }
        let all = RecentCommands.all(defaults: d)
        XCTAssertEqual(all.count, 8)
        XCTAssertEqual(all.first, "cmd 11")
    }

    func testIgnoresBlanks() {
        let d = defaults()
        RecentCommands.record("   ", defaults: d)
        XCTAssertTrue(RecentCommands.all(defaults: d).isEmpty)
    }

    func testCompactPaletteUsesExactCompactGeometryAndPreservesRecentOrder() {
        let layout = CommandPaletteLayout.compact
        let commands = (0..<8).map { "command \($0)" }

        XCTAssertEqual(layout.width, 500)
        XCTAssertEqual(layout.rowHeight, 30)
        XCTAssertEqual(layout.headerHeight, 64)
        XCTAssertEqual(layout.maxVisibleRecents, 4)
        XCTAssertEqual(layout.visibleCommands(commands), Array(commands.prefix(4)))
        XCTAssertEqual(layout.contentHeight(recentCount: 4), 230)
        XCTAssertEqual(layout.contentHeight(recentCount: 8), 230)
        XCTAssertEqual(layout.contentHeight(recentCount: 0), 88)
        XCTAssertEqual(layout.contentHeight(recentCount: -3), 88)
    }
}

@MainActor
final class ManualMuteTests: XCTestCase {

    func testMutedEngineIgnoresSummon() {
        let engine = WakeWordEngine()
        var woke = false
        engine.onWake = { woke = true }
        engine.manuallyMuted = true
        engine.summon()
        XCTAssertFalse(woke, "muted engine must ignore summon")
        engine.manuallyMuted = false
        engine.summon()
        XCTAssertTrue(woke)
    }
}
