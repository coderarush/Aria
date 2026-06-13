import XCTest
@testable import Aria

/// Unit tests for `ConnectorSetup` — the pure, view-independent logic behind the
/// Connectors pane's client-ID setup + connect flow. No network, no Keychain,
/// no SwiftUI is touched here.
final class ConnectorSetupTests: XCTestCase {

    // MARK: Client-ID / secret validation

    func testSanitizeTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(ConnectorSetup.sanitize("  abc123  "), "abc123")
        XCTAssertEqual(ConnectorSetup.sanitize("\n  paste\t\n"), "paste")
        XCTAssertEqual(ConnectorSetup.sanitize("clean"), "clean")
    }

    func testValidClientIDRejectsBlankOrWhitespace() {
        XCTAssertFalse(ConnectorSetup.isValidClientID(""))
        XCTAssertFalse(ConnectorSetup.isValidClientID("   "))
        XCTAssertFalse(ConnectorSetup.isValidClientID("\n\t "))
    }

    func testValidClientIDAcceptsNonEmptyAfterTrim() {
        XCTAssertTrue(ConnectorSetup.isValidClientID("x.apps.googleusercontent.com"))
        XCTAssertTrue(ConnectorSetup.isValidClientID("   padded-but-real   "))
    }

    func testRequiresSecretMatchesProvider() {
        XCTAssertFalse(ConnectorSetup.requiresSecret(.google)) // PKCE, no secret
        XCTAssertTrue(ConnectorSetup.requiresSecret(.notion))
        XCTAssertTrue(ConnectorSetup.requiresSecret(.slack))
    }

    func testCanSaveGoogleNeedsOnlyClientID() {
        XCTAssertTrue(ConnectorSetup.canSave(.google, clientID: "abc", secret: ""))
        XCTAssertFalse(ConnectorSetup.canSave(.google, clientID: "  ", secret: ""))
    }

    func testCanSaveNotionRequiresBothFields() {
        XCTAssertFalse(ConnectorSetup.canSave(.notion, clientID: "abc", secret: ""))
        XCTAssertFalse(ConnectorSetup.canSave(.notion, clientID: "", secret: "sek"))
        XCTAssertTrue(ConnectorSetup.canSave(.notion, clientID: "abc", secret: "sek"))
    }

    func testCanSaveSlackRequiresBothFields() {
        XCTAssertFalse(ConnectorSetup.canSave(.slack, clientID: "id", secret: "   "))
        XCTAssertTrue(ConnectorSetup.canSave(.slack, clientID: "id", secret: "sek"))
    }

    // MARK: Keychain account keys

    func testKeychainAccountKeysMatchBackendConvention() {
        // Must mirror ConnectorProvider.clientIDKeychainAccount so saving here
        // flips isConfigured → true in the (untouched) backend.
        XCTAssertEqual(ConnectorSetup.clientIDAccount(.google), "connector_google_client_id")
        XCTAssertEqual(ConnectorSetup.clientIDAccount(.notion), "connector_notion_client_id")
        XCTAssertEqual(ConnectorSetup.clientIDAccount(.slack), "connector_slack_client_id")
        XCTAssertEqual(ConnectorSetup.clientSecretAccount(.notion), "connector_notion_client_secret")
        XCTAssertEqual(ConnectorSetup.clientSecretAccount(.slack), "connector_slack_client_secret")
    }

    func testClientIDAccountMatchesGoogleConnector() {
        // Cross-check against the live provider so a rename can't silently break.
        let google = GoogleConnector()
        XCTAssertEqual(ConnectorSetup.clientIDAccount(.google), google.clientIDKeychainAccount)
    }

    // MARK: Status → presentation

    private func status(configured: Bool, connected: Bool,
                        scopes: [String] = []) -> ConnectorStatus {
        ConnectorStatus(id: .google, displayName: "Google",
                        isConfigured: configured, isConnected: connected,
                        scopes: scopes, expiry: nil)
    }

    func testStatusComingSoonWhenNoConnectorID() {
        XCTAssertEqual(ConnectorSetup.status(connectorID: nil, live: nil), .comingSoon)
        XCTAssertEqual(ConnectorSetup.status(connectorID: nil,
                                             live: status(configured: true, connected: true)),
                       .comingSoon)
    }

    func testStatusComingSoonWhenNoLiveSnapshot() {
        XCTAssertEqual(ConnectorSetup.status(connectorID: .google, live: nil), .comingSoon)
    }

    func testStatusNotConfiguredWhenNoClientID() {
        XCTAssertEqual(
            ConnectorSetup.status(connectorID: .google,
                                  live: status(configured: false, connected: false)),
            .notConfigured)
    }

    func testStatusAvailableWhenConfiguredNotConnected() {
        XCTAssertEqual(
            ConnectorSetup.status(connectorID: .google,
                                  live: status(configured: true, connected: false)),
            .available)
    }

    func testStatusConnectedWinsEvenIfConfiguredFlagWeird() {
        XCTAssertEqual(
            ConnectorSetup.status(connectorID: .google,
                                  live: status(configured: true, connected: true)),
            .connected)
    }

    func testButtonLabels() {
        XCTAssertEqual(ConnectorSetup.buttonLabel(for: .connected), "Disconnect")
        XCTAssertEqual(ConnectorSetup.buttonLabel(for: .available), "Connect")
        XCTAssertEqual(ConnectorSetup.buttonLabel(for: .notConfigured), "Add client ID")
        XCTAssertEqual(ConnectorSetup.buttonLabel(for: .comingSoon), "Coming soon")
    }

    func testPillLabels() {
        XCTAssertEqual(ConnectorSetup.pillLabel(for: .connected), "Connected")
        XCTAssertEqual(ConnectorSetup.pillLabel(for: .available), "Ready")
        XCTAssertEqual(ConnectorSetup.pillLabel(for: .notConfigured), "Setup needed")
        XCTAssertEqual(ConnectorSetup.pillLabel(for: .comingSoon), "Coming soon")
    }

    // MARK: Connected hint

    func testConnectedHintNilWhenNotConnected() {
        XCTAssertNil(ConnectorSetup.connectedHint(status(configured: true, connected: false)))
    }

    func testConnectedHintMapsGoogleScopesAndDedupes() {
        let hint = ConnectorSetup.connectedHint(
            status(configured: true, connected: true,
                   scopes: ["https://www.googleapis.com/auth/gmail.readonly",
                            "https://www.googleapis.com/auth/calendar.readonly"]))
        XCTAssertEqual(hint, "Gmail · Calendar")
    }

    func testConnectedHintDedupesRepeatedFriendlyNames() {
        let hint = ConnectorSetup.connectedHint(
            status(configured: true, connected: true,
                   scopes: ["gmail.readonly", "gmail.send"]))
        XCTAssertEqual(hint, "Gmail")
    }

    func testConnectedHintCountsUnknownScopes() {
        XCTAssertEqual(
            ConnectorSetup.connectedHint(status(configured: true, connected: true,
                                                scopes: ["weird:one", "weird:two"])),
            "2 permissions granted")
        XCTAssertEqual(
            ConnectorSetup.connectedHint(status(configured: true, connected: true,
                                                scopes: ["weird:one"])),
            "1 permission granted")
    }

    func testConnectedHintFallsBackToLinkedWhenNoScopes() {
        XCTAssertEqual(
            ConnectorSetup.connectedHint(status(configured: true, connected: true, scopes: [])),
            "Linked")
    }

    func testFriendlyScopeRecognizesKnownAndRejectsUnknown() {
        XCTAssertEqual(ConnectorSetup.friendlyScope("…/gmail.readonly"), "Gmail")
        XCTAssertEqual(ConnectorSetup.friendlyScope("…/calendar.events"), "Calendar")
        XCTAssertEqual(ConnectorSetup.friendlyScope("chat:write"), "Slack")
        XCTAssertNil(ConnectorSetup.friendlyScope("totally:unknown"))
    }

    // MARK: Setup help

    func testSetupStepsExistForEveryProvider() {
        for id in ConnectorID.allCases {
            let steps = ConnectorSetup.setupSteps(for: id)
            XCTAssertGreaterThanOrEqual(steps.count, 3, "\(id) should have 3-4 steps")
            XCTAssertLessThanOrEqual(steps.count, 4, "\(id) should stay short (3-4 steps)")
            XCTAssertFalse(steps.contains { $0.isEmpty })
        }
    }

    func testGoogleStepsMentionDesktopAndPKCE() {
        let steps = ConnectorSetup.setupSteps(for: .google).joined(separator: " ").lowercased()
        XCTAssertTrue(steps.contains("desktop"))
        XCTAssertTrue(steps.contains("pkce") || steps.contains("no secret"))
    }

    func testConsoleNamesAreNonEmpty() {
        for id in ConnectorID.allCases {
            XCTAssertFalse(ConnectorSetup.consoleName(for: id).isEmpty)
        }
    }
}
