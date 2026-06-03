import XCTest
@testable import Aria

final class SettingsTests: XCTestCase {

    @MainActor
    func testAppSettingsDefaultsAndPersistence() {
        let suite = UserDefaults(suiteName: "aria-app-\(UUID().uuidString)")!
        let s = AppSettings(defaults: suite)
        XCTAssertEqual(s.orbPosition, .bottomCenter)
        XCTAssertEqual(s.orbSize, .medium)
        XCTAssertEqual(s.responseDuration, 8, accuracy: 0.001)
        XCTAssertFalse(s.privacyMode)
        XCTAssertFalse(s.onboardingComplete)

        s.privacyMode = true
        s.orbSize = .large
        s.disabledTools.insert("shell")

        // Reload from the same suite — values persist.
        let reloaded = AppSettings(defaults: suite)
        XCTAssertTrue(reloaded.privacyMode)
        XCTAssertEqual(reloaded.orbSize, .large)
        XCTAssertTrue(reloaded.disabledTools.contains("shell"))
    }

    func testOrbSizeDiameters() {
        XCTAssertEqual(AppSettings.OrbSize.small.diameter, 64)
        XCTAssertEqual(AppSettings.OrbSize.large.diameter, 108)
    }

    func testMirrorSettingsRoundTrip() {
        let suite = UserDefaults(suiteName: "aria-mirror-\(UUID().uuidString)")!
        var s = MirrorSettings.load(suite)
        XCTAssertFalse(s.enabled)
        XCTAssertEqual(s.port, 8765)
        s.enabled = true; s.port = 9000; s.save(suite)
        let reloaded = MirrorSettings.load(suite)
        XCTAssertTrue(reloaded.enabled)
        XCTAssertEqual(reloaded.port, 9000)
    }

    func testMirrorBridgeStubState() {
        let bridge = MirrorBridge()
        XCTAssertEqual(bridge.state, .notConnected)
        bridge.startServer(port: 8765)   // no-op stub
        XCTAssertEqual(bridge.port, 8765)
    }
}
