import XCTest
@testable import Aria

final class AppFocusMonitorTests: XCTestCase {

    func testFocusLineFormatsDuration() {
        let now = Date()
        XCTAssertEqual(
            AppFocusMonitor.focusLine(appName: "Xcode", since: now.addingTimeInterval(-12 * 60), now: now),
            "Right now you're working in Xcode (12m).")
        XCTAssertEqual(
            AppFocusMonitor.focusLine(appName: "Mail", since: now.addingTimeInterval(-30), now: now),
            "Right now you're working in Mail (just switched).")
        XCTAssertEqual(
            AppFocusMonitor.focusLine(appName: "Figma", since: now.addingTimeInterval(-3900), now: now),
            "Right now you're working in Figma (1h 5m).")
    }

    func testFocusLineNilForEmptyApp() {
        XCTAssertNil(AppFocusMonitor.focusLine(appName: "   ", since: Date(), now: Date()))
    }

    func testActivationTracksAppAndResetsSinceOnSwitch() async {
        let m = AppFocusMonitor()
        let t0 = Date()
        await m.noteActivation(appName: "Xcode", bundleId: "com.apple.dt.Xcode", at: t0)
        let s1 = await m.snapshot()
        XCTAssertEqual(s1?.appName, "Xcode")
        XCTAssertEqual(s1?.since, t0)

        // Re-activating the SAME app keeps the original "since" (same focus session).
        let t1 = t0.addingTimeInterval(60)
        await m.noteActivation(appName: "Xcode", bundleId: "com.apple.dt.Xcode", at: t1)
        let s2 = await m.snapshot()
        XCTAssertEqual(s2?.since, t0, "re-activating the same app should not reset the timer")

        // Switching apps resets "since" to the switch moment.
        let t2 = t1.addingTimeInterval(5)
        await m.noteActivation(appName: "Mail", bundleId: "com.apple.mail", at: t2)
        let s3 = await m.snapshot()
        XCTAssertEqual(s3?.appName, "Mail")
        XCTAssertEqual(s3?.since, t2)
    }

    func testBlankActivationIgnored() async {
        let m = AppFocusMonitor()
        await m.noteActivation(appName: "  ", bundleId: nil, at: Date())
        let s = await m.snapshot()
        XCTAssertNil(s, "a blank app name should not become the focus")
    }

    func testSummaryLineNilWhenNoFocus() async {
        let m = AppFocusMonitor()
        let line = await m.summaryLine(now: Date())
        XCTAssertNil(line)
    }

    func testStartupSeedDoesNotClobberFresherActivation() async {
        // start() installs the observer before seeding the frontmost app. If a real
        // switch lands during that window, the (older) seed must not overwrite it.
        let m = AppFocusMonitor()
        let t0 = Date()
        await m.noteActivation(appName: "Mail", bundleId: "com.apple.mail", at: t0)  // arrived during await
        await m.seedIfUnseen(appName: "Xcode", bundleId: "com.apple.dt.Xcode", at: t0.addingTimeInterval(-5))
        let s = await m.snapshot()
        XCTAssertEqual(s?.appName, "Mail", "fresher activation must survive the startup seed")
        XCTAssertEqual(s?.since, t0)
    }

    func testSeedSetsFocusWhenNothingSeenYet() async {
        let m = AppFocusMonitor()
        await m.seedIfUnseen(appName: "Xcode", bundleId: "com.apple.dt.Xcode")
        let s = await m.snapshot()
        XCTAssertEqual(s?.appName, "Xcode")
    }
}
