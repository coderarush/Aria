import XCTest
@testable import Aria

final class SettingsTests: XCTestCase {

    func testSettingsGroupsCoverEveryDestinationOnce() {
        let grouped = SettingsView.Section.grouped

        XCTAssertEqual(Set(grouped.flatMap(\.sections)), Set(SettingsView.Section.allCases))
        XCTAssertEqual(grouped.map(\.title), ["Basics", "Workflows", "Privacy & access", "Advanced"])
    }

    @MainActor
    func testAppSettingsDefaultsAndPersistence() {
        let suite = UserDefaults(suiteName: "aria-app-\(UUID().uuidString)")!
        let s = AppSettings(defaults: suite)
        XCTAssertEqual(s.orbPosition, .bottomCenter)
        XCTAssertEqual(s.orbSize, .medium)
        XCTAssertEqual(s.responseDuration, 8, accuracy: 0.001)
        XCTAssertFalse(s.privacyMode)
        XCTAssertFalse(s.onboardingComplete)
        XCTAssertFalse(s.autonomousMode)
        XCTAssertFalse(s.backgroundAgentsEnabled)

        s.privacyMode = true
        s.orbSize = .large
        s.disabledTools.insert("shell")
        s.backgroundAgentsEnabled = true

        // Reload from the same suite — values persist.
        let reloaded = AppSettings(defaults: suite)
        XCTAssertTrue(reloaded.privacyMode)
        XCTAssertEqual(reloaded.orbSize, .large)
        XCTAssertTrue(reloaded.disabledTools.contains("shell"))
        XCTAssertTrue(reloaded.backgroundAgentsEnabled)
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

    func testMirrorBridgeIsUnavailableUntilTransportExists() {
        XCTAssertEqual(MirrorBridge.availability, .unavailable)
    }
}
