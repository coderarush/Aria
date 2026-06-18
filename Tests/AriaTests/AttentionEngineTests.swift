import XCTest
@testable import Aria

final class AttentionEngineTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    func testNoFocusIsIdleAndInterruptible() async {
        let mon = AppFocusMonitor()
        let st = await AttentionEngine(monitor: mon).state(now: t)
        XCTAssertEqual(st.depth, .idle)
        XCTAssertTrue(st.shouldInterrupt)         // suggest more during idle
        XCTAssertNil(st.activeApp)
    }

    func testShortFocusIsShallowAndInterruptible() async {
        let mon = AppFocusMonitor()
        await mon.noteActivation(appName: "Mail", bundleId: nil, at: t)
        let st = await AttentionEngine(monitor: mon, deepThreshold: 600).state(now: t.addingTimeInterval(120))
        XCTAssertEqual(st.depth, .shallow)
        XCTAssertTrue(st.shouldInterrupt)
        XCTAssertEqual(st.activeApp, "Mail")
    }

    func testLongFocusIsDeepAndSuppressesInterrupt() async {
        let mon = AppFocusMonitor()
        await mon.noteActivation(appName: "Xcode", bundleId: nil, at: t)
        let st = await AttentionEngine(monitor: mon, deepThreshold: 600).state(now: t.addingTimeInterval(900))
        XCTAssertEqual(st.depth, .deep)
        XCTAssertFalse(st.shouldInterrupt)        // interrupt less during focus
        XCTAssertEqual(Int(st.focusMinutes), 15)
    }

    func testShouldInterruptConvenience() async {
        let mon = AppFocusMonitor()
        await mon.noteActivation(appName: "Xcode", bundleId: nil, at: t)
        let deep = await AttentionEngine(monitor: mon, deepThreshold: 600).shouldInterrupt(now: t.addingTimeInterval(1200))
        XCTAssertFalse(deep)
    }
}
