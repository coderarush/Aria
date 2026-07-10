import XCTest
@testable import Aria

/// Tests for v11.1.1 hosted-OAuth-relay client support: `ConnectorMode` resolution,
/// the pure `RelayConfig` URL builders, the mode-aware `AuthConfig` shape (relay vs
/// bring-your-own), and mode-aware `isConfigured`. All pure / in-memory — no network,
/// no browser, no Keychain. The bring-your-own path is asserted byte-identical as a
/// regression guard.
final class ConnectorRelayModeTests: XCTestCase {

    /// A throwaway UserDefaults suite so tests never touch `.standard`.
    private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: - ConnectorMode.current

    func testModeDefaultsToBringYourOwnWhenUnset() {
        let d = makeDefaults()
        XCTAssertEqual(ConnectorMode.current(defaults: d), .bringYourOwn)
    }

    func testModeDefaultsToBringYourOwnWhenGarbage() {
        let d = makeDefaults()
        d.set("nonsense", forKey: ConnectorMode.defaultsKey)
        XCTAssertEqual(ConnectorMode.current(defaults: d), .bringYourOwn)
    }

    func testModeReadsRelayOverride() {
        let d = makeDefaults()
        d.set("relay", forKey: ConnectorMode.defaultsKey)
        XCTAssertEqual(ConnectorMode.current(defaults: d), .relay)
    }

    func testModeReadsBringYourOwnOverride() {
        let d = makeDefaults()
        d.set("bringYourOwn", forKey: ConnectorMode.defaultsKey)
        XCTAssertEqual(ConnectorMode.current(defaults: d), .bringYourOwn)
    }

    // MARK: - RelayConfig URL builders

    func testRelayBaseDefault() {
        let d = makeDefaults()
        XCTAssertEqual(RelayConfig.base(defaults: d), "https://relay.aria.app")
    }

    func testRelayBaseOverrideAndTrailingSlashTrim() {
        let d = makeDefaults()
        d.set("https://staging.example.com/", forKey: RelayConfig.baseDefaultsKey)
        XCTAssertEqual(RelayConfig.base(defaults: d), "https://staging.example.com")
    }

    func testRelayAuthorizeURLShape() throws {
        let d = makeDefaults()
        let url = try XCTUnwrap(RelayConfig.authorizeURL(
            provider: .google,
            challenge: "CHAL",
            state: "STATE",
            redirect: "http://127.0.0.1:5050/callback",
            defaults: d))
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.scheme, "https")
        XCTAssertEqual(comps.host, "relay.aria.app")
        XCTAssertEqual(comps.path, "/authorize")
        let items = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["provider"], "google")
        XCTAssertEqual(items["code_challenge"], "CHAL")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["state"], "STATE")
        XCTAssertEqual(items["redirect_uri"], "http://127.0.0.1:5050/callback")
        // The relay needs no user client ID — none is sent on the authorize URL.
        XCTAssertNil(items["client_id"])
        XCTAssertNil(items["client_secret"])
    }

    func testRelayAuthorizeURLHonorsBaseOverride() throws {
        let d = makeDefaults()
        d.set("https://staging.example.com", forKey: RelayConfig.baseDefaultsKey)
        let url = try XCTUnwrap(RelayConfig.authorizeURL(
            provider: .notion, challenge: "C", state: "S",
            redirect: "http://127.0.0.1:1/callback", defaults: d))
        XCTAssertEqual(url.host, "staging.example.com")
        let items = Dictionary(uniqueKeysWithValues:
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["provider"], "notion")
    }

    func testRelayTokenURL() {
        let d = makeDefaults()
        XCTAssertEqual(RelayConfig.tokenURL(defaults: d)?.absoluteString,
                       "https://relay.aria.app/token")
        XCTAssertEqual(RelayConfig.tokenEndpoint(defaults: d),
                       "https://relay.aria.app/token")
    }

    // MARK: - Relay-mode AuthConfig

    func testRelayAuthConfigCarriesRelayEndpointsAndNoSecret() {
        let d = makeDefaults()
        // Google: PKCE-only provider.
        let google = GoogleConnector()
        let gConfig = google.authConfig(clientID: "ignored", mode: .relay, defaults: d)
        XCTAssertEqual(gConfig.authEndpoint, "https://relay.aria.app/authorize")
        XCTAssertEqual(gConfig.tokenEndpoint, "https://relay.aria.app/token")
        XCTAssertNil(gConfig.clientSecret, "relay mode must never send a client secret")
        XCTAssertEqual(gConfig.clientID, "google", "relay maps the provider id to its client")
        XCTAssertEqual(gConfig.scopes, google.scopes)
        XCTAssertEqual(gConfig.extraAuthParameters, google.extraAuthParameters)

        // Notion: confidential provider in BYO — still NO secret in relay mode.
        let notion = NotionConnector()
        let nConfig = notion.authConfig(clientID: "ignored", mode: .relay, defaults: d)
        XCTAssertEqual(nConfig.authEndpoint, "https://relay.aria.app/authorize")
        XCTAssertEqual(nConfig.tokenEndpoint, "https://relay.aria.app/token")
        XCTAssertNil(nConfig.clientSecret,
                     "even confidential providers send no secret in relay mode — the relay owns it")
        XCTAssertEqual(nConfig.clientID, "notion")
    }

    func testRelayAuthConfigHonorsBaseOverride() {
        let d = makeDefaults()
        d.set("https://staging.example.com", forKey: RelayConfig.baseDefaultsKey)
        let cfg = GoogleConnector().authConfig(clientID: "x", mode: .relay, defaults: d)
        XCTAssertEqual(cfg.authEndpoint, "https://staging.example.com/authorize")
        XCTAssertEqual(cfg.tokenEndpoint, "https://staging.example.com/token")
    }

    // MARK: - Bring-your-own AuthConfig (regression guard — must be unchanged)

    func testBringYourOwnAuthConfigUnchanged_Google() {
        let google = GoogleConnector()
        // The mode-aware builder for .bringYourOwn must equal today's authConfig(clientID:).
        let viaMode = google.authConfig(clientID: "client-123", mode: .bringYourOwn)
        let viaLegacy = google.authConfig(clientID: "client-123")
        XCTAssertEqual(viaMode.clientID, viaLegacy.clientID)
        XCTAssertEqual(viaMode.clientID, "client-123")
        XCTAssertEqual(viaMode.authEndpoint, viaLegacy.authEndpoint)
        XCTAssertEqual(viaMode.authEndpoint, "https://accounts.google.com/o/oauth2/v2/auth")
        XCTAssertEqual(viaMode.tokenEndpoint, viaLegacy.tokenEndpoint)
        XCTAssertEqual(viaMode.tokenEndpoint, "https://oauth2.googleapis.com/token")
        XCTAssertEqual(viaMode.scopes, viaLegacy.scopes)
        XCTAssertEqual(viaMode.extraAuthParameters, viaLegacy.extraAuthParameters)
        // Google is PKCE-only: no secret in either path.
        XCTAssertNil(viaMode.clientSecret)
        XCTAssertNil(viaLegacy.clientSecret)
    }

    func testBringYourOwnAuthConfigUsesProviderEndpoints_Notion() {
        let notion = NotionConnector()
        let cfg = notion.authConfig(clientID: "notion-client", mode: .bringYourOwn)
        XCTAssertEqual(cfg.clientID, "notion-client")
        XCTAssertEqual(cfg.authEndpoint, "https://api.notion.com/v1/oauth/authorize")
        XCTAssertEqual(cfg.tokenEndpoint, "https://api.notion.com/v1/oauth/token")
        // No Keychain secret wired in this test, so resolvedClientSecret() is nil —
        // confirms the BYO builder reads the provider's secret path (not a relay constant).
        XCTAssertNil(cfg.clientSecret)
    }

    // MARK: - isConfigured semantics

    func testIsConfiguredTrueInRelayWithoutClientID() {
        let d = makeDefaults()
        // No client ID resolvable (keychain read returns nil, empty defaults).
        let provider = GoogleConnector()
        XCTAssertTrue(provider.isConfigured(mode: .relay,
                                            keychainRead: { _ in nil },
                                            defaults: d),
                      "relay mode is configured without a user client ID")
    }

    func testIsConfiguredFalseInBYOWithoutClientID() {
        let d = makeDefaults()
        let provider = GoogleConnector()
        XCTAssertFalse(provider.isConfigured(mode: .bringYourOwn,
                                             keychainRead: { _ in nil },
                                             defaults: d),
                       "bring-your-own needs a user client ID")
    }

    func testIsConfiguredTrueInBYOWithClientID() {
        let d = makeDefaults()
        d.set("client-xyz", forKey: GoogleConnector().clientIDDefaultsKey)
        let provider = GoogleConnector()
        XCTAssertTrue(provider.isConfigured(mode: .bringYourOwn,
                                            keychainRead: { _ in nil },
                                            defaults: d))
    }
}
