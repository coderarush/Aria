import XCTest
import CryptoKit
@testable import Aria

final class ConnectorPKCETests: XCTestCase {

    func testCodeChallengeIsCorrectS256() {
        // RFC 7636 Appendix B canonical vector.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        XCTAssertEqual(OAuth2.codeChallengeS256(for: verifier), expected)
    }

    func testChallengeIsURLSafeAndUnpadded() {
        let pkce = OAuth2.makePKCE()
        XCTAssertEqual(pkce.method, "S256")
        XCTAssertFalse(pkce.challenge.contains("+"))
        XCTAssertFalse(pkce.challenge.contains("/"))
        XCTAssertFalse(pkce.challenge.contains("="))
        XCTAssertFalse(pkce.verifier.contains("+"))
        XCTAssertFalse(pkce.verifier.contains("/"))
        XCTAssertFalse(pkce.verifier.contains("="))
    }

    func testVerifierLengthInSpec() {
        // RFC 7636 §4.1: 43–128 chars. 32 random bytes → 43 base64url chars.
        let verifier = OAuth2.randomCodeVerifier()
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertLessThanOrEqual(verifier.count, 128)
    }

    func testVerifiersAreUnique() {
        XCTAssertNotEqual(OAuth2.randomCodeVerifier(), OAuth2.randomCodeVerifier())
    }

    func testChallengeMatchesManualSHA256() {
        let verifier = OAuth2.randomCodeVerifier()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        XCTAssertEqual(OAuth2.codeChallengeS256(for: verifier),
                       OAuth2.base64URLEncode(Data(digest)))
    }
}

final class ConnectorAuthURLTests: XCTestCase {

    func testAuthorizationURLHasRequiredParams() throws {
        let url = OAuth2.buildAuthorizationURL(
            authEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
            clientID: "client-123",
            redirectURI: "http://127.0.0.1:54321/callback",
            scopes: ["scope.a", "scope.b"],
            challenge: "CHALLENGE",
            state: "STATE",
            extraParameters: ["access_type": "offline", "prompt": "consent"]
        )
        let comps = try XCTUnwrap(url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        let items = comps.queryItems ?? []
        func v(_ n: String) -> String? { items.first { $0.name == n }?.value }

        XCTAssertEqual(comps.host, "accounts.google.com")
        XCTAssertEqual(v("response_type"), "code")
        XCTAssertEqual(v("client_id"), "client-123")
        XCTAssertEqual(v("redirect_uri"), "http://127.0.0.1:54321/callback")
        XCTAssertEqual(v("scope"), "scope.a scope.b")
        XCTAssertEqual(v("code_challenge"), "CHALLENGE")
        XCTAssertEqual(v("code_challenge_method"), "S256")
        XCTAssertEqual(v("state"), "STATE")
        XCTAssertEqual(v("access_type"), "offline")
        XCTAssertEqual(v("prompt"), "consent")
    }

    func testAuthorizationURLNilForBadEndpoint() {
        XCTAssertNil(OAuth2.buildAuthorizationURL(
            authEndpoint: "",
            clientID: "c", redirectURI: "r", scopes: [], challenge: "x", state: "s"))
    }

    func testGoogleProviderConfigBuildsValidAuthURL() throws {
        let google = GoogleConnector()
        let config = google.authConfig(clientID: "abc.apps.googleusercontent.com")
        let url = OAuth2.buildAuthorizationURL(
            authEndpoint: config.authEndpoint,
            clientID: config.clientID,
            redirectURI: "http://127.0.0.1:9/callback",
            scopes: config.scopes,
            challenge: "C",
            state: "S",
            extraParameters: config.extraAuthParameters)
        let comps = try XCTUnwrap(url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        let scope = comps.queryItems?.first { $0.name == "scope" }?.value
        XCTAssertEqual(scope, google.scopes.joined(separator: " "))
        XCTAssertTrue(scope?.contains("gmail.readonly") == true)
        XCTAssertTrue(scope?.contains("calendar.readonly") == true)
    }
}

final class ConnectorTokenParseTests: XCTestCase {

    func testParsesFullTokenResponse() throws {
        let json = """
        {"access_token":"AT","refresh_token":"RT","expires_in":3599,
         "scope":"scope.a scope.b","token_type":"Bearer"}
        """
        let token = try XCTUnwrap(OAuth2.parseTokenResponse(Data(json.utf8)))
        XCTAssertEqual(token.accessToken, "AT")
        XCTAssertEqual(token.refreshToken, "RT")
        XCTAssertEqual(token.expiresIn, 3599)
        XCTAssertEqual(token.scopes, ["scope.a", "scope.b"])
        XCTAssertEqual(token.tokenType, "Bearer")
    }

    func testParsesResponseMissingRefreshToken() throws {
        // Google omits refresh_token on refreshes — must parse to nil, not fail.
        let json = """
        {"access_token":"AT2","expires_in":3600,"scope":"s","token_type":"Bearer"}
        """
        let token = try XCTUnwrap(OAuth2.parseTokenResponse(Data(json.utf8)))
        XCTAssertEqual(token.accessToken, "AT2")
        XCTAssertNil(token.refreshToken)
    }

    func testEmptyRefreshTokenTreatedAsNil() throws {
        let json = #"{"access_token":"AT","refresh_token":"","expires_in":10}"#
        let token = try XCTUnwrap(OAuth2.parseTokenResponse(Data(json.utf8)))
        XCTAssertNil(token.refreshToken)
    }

    func testRejectsBodyWithoutAccessToken() {
        XCTAssertNil(OAuth2.parseTokenResponse(Data(#"{"error":"invalid_grant"}"#.utf8)))
        XCTAssertNil(OAuth2.parseTokenResponse(Data("not json".utf8)))
    }

    func testExpiresInDefaultsWhenMissing() throws {
        let token = try XCTUnwrap(OAuth2.parseTokenResponse(Data(#"{"access_token":"AT"}"#.utf8)))
        XCTAssertEqual(token.expiresIn, 3600)
    }

    func testParsesExpiresInAsString() throws {
        let token = try XCTUnwrap(OAuth2.parseTokenResponse(Data(#"{"access_token":"AT","expires_in":"120"}"#.utf8)))
        XCTAssertEqual(token.expiresIn, 120)
    }
}

final class ConnectorRedirectParseTests: XCTestCase {

    func testParsesCodeWithMatchingState() {
        let result = OAuth2.parseRedirect(query: "code=AUTHCODE&state=S1", expectedState: "S1")
        XCTAssertEqual(try? result.get(), "AUTHCODE")
    }

    func testRejectsStateMismatch() {
        let result = OAuth2.parseRedirect(query: "code=X&state=WRONG", expectedState: "RIGHT")
        if case .failure(let e) = result { XCTAssertEqual(e, .stateMismatch) }
        else { XCTFail("expected stateMismatch") }
    }

    func testSurfacesAuthorizationDenied() {
        let result = OAuth2.parseRedirect(query: "error=access_denied&state=S", expectedState: "S")
        if case .failure(let e) = result { XCTAssertEqual(e, .authorizationDenied("access_denied")) }
        else { XCTFail("expected authorizationDenied") }
    }

    func testMissingCodeFails() {
        let result = OAuth2.parseRedirect(query: "state=S", expectedState: "S")
        if case .failure(let e) = result { XCTAssertEqual(e, .missingCode) }
        else { XCTFail("expected missingCode") }
    }
}

final class ConnectorTokenStoreTests: XCTestCase {

    /// An in-memory token store so tests never touch the real Keychain.
    private func memoryStore() -> (ConnectorTokenStore, () -> [String: String]) {
        final class Box: @unchecked Sendable { var map: [String: String] = [:] }
        let box = Box()
        let lock = NSLock()
        let store = ConnectorTokenStore(
            read: { key in lock.lock(); defer { lock.unlock() }; return box.map[key] },
            write: { key, value in lock.lock(); box.map[key] = value; lock.unlock() },
            remove: { key in lock.lock(); box.map[key] = nil; lock.unlock() }
        )
        return (store, { lock.lock(); defer { lock.unlock() }; return box.map })
    }

    func testRoundTripPreservesAllFields() throws {
        let (store, _) = memoryStore()
        let expiry = Date(timeIntervalSince1970: 1_900_000_000)
        let tokens = ConnectorTokens(accessToken: "AT", refreshToken: "RT",
                                     expiry: expiry, scopes: ["a", "b"])
        try store.save(tokens, for: .google)
        let loaded = try XCTUnwrap(store.load(.google))
        XCTAssertEqual(loaded, tokens)
        XCTAssertEqual(loaded.accessToken, "AT")
        XCTAssertEqual(loaded.refreshToken, "RT")
        XCTAssertEqual(loaded.expiry, expiry)
        XCTAssertEqual(loaded.scopes, ["a", "b"])
    }

    func testLoadMissingReturnsNil() {
        let (store, _) = memoryStore()
        XCTAssertNil(store.load(.notion))
        XCTAssertFalse(store.isConnected(.notion))
    }

    func testDeleteRemovesTokens() throws {
        let (store, _) = memoryStore()
        try store.save(ConnectorTokens(accessToken: "AT", refreshToken: nil,
                                       expiry: Date().addingTimeInterval(3600), scopes: []), for: .slack)
        XCTAssertTrue(store.isConnected(.slack))
        store.delete(.slack)
        XCTAssertFalse(store.isConnected(.slack))
    }

    func testProvidersUseDistinctKeys() throws {
        let (store, raw) = memoryStore()
        try store.save(ConnectorTokens(accessToken: "G", refreshToken: nil, expiry: Date(), scopes: []), for: .google)
        try store.save(ConnectorTokens(accessToken: "N", refreshToken: nil, expiry: Date(), scopes: []), for: .notion)
        XCTAssertEqual(raw().count, 2)
        XCTAssertEqual(store.load(.google)?.accessToken, "G")
        XCTAssertEqual(store.load(.notion)?.accessToken, "N")
    }
}

final class ConnectorExpiryTests: XCTestCase {

    func testFreshTokenNotExpired() {
        let now = Date()
        let tokens = ConnectorTokens(accessToken: "AT", refreshToken: "RT",
                                     expiry: now.addingTimeInterval(3600), scopes: [])
        XCTAssertFalse(tokens.isExpired(now: now))
    }

    func testPastExpiryIsExpired() {
        let now = Date()
        let tokens = ConnectorTokens(accessToken: "AT", refreshToken: "RT",
                                     expiry: now.addingTimeInterval(-10), scopes: [])
        XCTAssertTrue(tokens.isExpired(now: now))
    }

    func testSkewWindowCountsAsExpired() {
        let now = Date()
        // Expires in 30s, but the 60s skew should treat it as expired now.
        let tokens = ConnectorTokens(accessToken: "AT", refreshToken: "RT",
                                     expiry: now.addingTimeInterval(30), scopes: [])
        XCTAssertTrue(tokens.isExpired(now: now, skew: 60))
        XCTAssertFalse(tokens.isExpired(now: now, skew: 0))
    }

    func testExpiryAnchoredFromResponse() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let response = OAuth2.TokenResponse(accessToken: "AT", refreshToken: "RT",
                                            expiresIn: 3600, scopes: ["s"], tokenType: "Bearer")
        let tokens = ConnectorTokens(from: response, now: now)
        XCTAssertEqual(tokens.expiry, now.addingTimeInterval(3600))
        XCTAssertEqual(tokens.refreshToken, "RT")
    }

    func testRefreshKeepsPreviousRefreshTokenWhenOmitted() {
        // A refresh response with no refresh_token must retain the old one.
        let response = OAuth2.TokenResponse(accessToken: "AT2", refreshToken: nil,
                                            expiresIn: 3600, scopes: ["s"], tokenType: "Bearer")
        let tokens = ConnectorTokens(from: response, previousRefreshToken: "OLD-RT")
        XCTAssertEqual(tokens.refreshToken, "OLD-RT")
        XCTAssertEqual(tokens.accessToken, "AT2")
    }
}

final class ConnectorProviderConfigTests: XCTestCase {

    func testNotConfiguredWhenNoClientID() {
        let google = GoogleConnector()
        let id = google.resolvedClientID(
            keychainRead: { _ in nil },
            defaults: UserDefaults(suiteName: "conn-\(UUID().uuidString)")!)
        XCTAssertNil(id)
    }

    func testKeychainClientIDWins() {
        let google = GoogleConnector()
        let defaults = UserDefaults(suiteName: "conn-\(UUID().uuidString)")!
        defaults.set("from-defaults", forKey: google.clientIDDefaultsKey)
        let id = google.resolvedClientID(keychainRead: { _ in "from-keychain" }, defaults: defaults)
        XCTAssertEqual(id, "from-keychain")
    }

    func testFallsBackToDefaults() {
        let google = GoogleConnector()
        let defaults = UserDefaults(suiteName: "conn-\(UUID().uuidString)")!
        defaults.set("from-defaults", forKey: google.clientIDDefaultsKey)
        let id = google.resolvedClientID(keychainRead: { _ in nil }, defaults: defaults)
        XCTAssertEqual(id, "from-defaults")
    }

    func testBlankClientIDTreatedAsUnconfigured() {
        let google = GoogleConnector()
        let id = google.resolvedClientID(
            keychainRead: { _ in "   " },
            defaults: UserDefaults(suiteName: "conn-\(UUID().uuidString)")!)
        XCTAssertNil(id)
    }

    func testAllProvidersPresent() {
        XCTAssertEqual(Set(ConnectorID.allCases), [.google, .notion, .slack])
        XCTAssertEqual(Connectors.provider(for: .google).displayName, "Google")
        XCTAssertEqual(Connectors.provider(for: .notion).displayName, "Notion")
        XCTAssertEqual(Connectors.provider(for: .slack).displayName, "Slack")
    }
}

final class GoogleResponseParseTests: XCTestCase {

    func testParsesGmailMetadata() throws {
        let json = """
        {"id":"m1","snippet":"hello there",
         "payload":{"headers":[{"name":"From","value":"a@b.com"},
                                {"name":"Subject","value":"Hi"}]}}
        """
        let msg = try XCTUnwrap(GoogleConnector.parseGmailMessage(Data(json.utf8)))
        XCTAssertEqual(msg.id, "m1")
        XCTAssertEqual(msg.from, "a@b.com")
        XCTAssertEqual(msg.subject, "Hi")
        XCTAssertEqual(msg.snippet, "hello there")
    }

    func testParsesCalendarEvents() {
        let json = """
        {"items":[{"summary":"Standup","start":{"dateTime":"2026-06-13T09:00:00Z"}},
                  {"summary":"All day","start":{"date":"2026-06-14"}}]}
        """
        let events = GoogleConnector.parseCalendarEvents(Data(json.utf8))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].summary, "Standup")
        XCTAssertEqual(events[0].start, "2026-06-13T09:00:00Z")
        XCTAssertEqual(events[1].start, "2026-06-14")
    }
}

final class ConnectorStoreActorTests: XCTestCase {

    private func memoryTokenStore() -> ConnectorTokenStore {
        final class Box: @unchecked Sendable { var values: [String: String] = [:] }
        let box = Box()
        let lock = NSLock()
        return ConnectorTokenStore(
            read: { key in lock.lock(); defer { lock.unlock() }; return box.values[key] },
            write: { key, value in lock.lock(); box.values[key] = value; lock.unlock() },
            remove: { key in lock.lock(); box.values[key] = nil; lock.unlock() }
        )
    }

    func testConnectThrowsNotConfigured() async {
        // The "no client ID ⇒ .notConfigured" contract is specific to bring-your-own
        // mode; in relay mode the relay supplies the client and connect
        // proceeds without a user client ID. Pin BYO for this contract test.
        let prior = UserDefaults.standard.string(forKey: ConnectorMode.defaultsKey)
        UserDefaults.standard.set(ConnectorMode.bringYourOwn.rawValue, forKey: ConnectorMode.defaultsKey)
        defer {
            if let prior { UserDefaults.standard.set(prior, forKey: ConnectorMode.defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: ConnectorMode.defaultsKey) }
        }
        let store = ConnectorStore(
            tokenStore: ConnectorTokenStore(read: { _ in nil }, write: { _, _ in }, remove: { _ in }),
            authorize: { _, _ in
                XCTFail("should not authorize when not configured")
                return OAuth2.TokenResponse(accessToken: "", refreshToken: nil, expiresIn: 0, scopes: [], tokenType: "Bearer")
            },
            // Pin "no client ID" hermetically: the real resolver reads the Keychain,
            // so a developer's stored Google client ID would otherwise satisfy BYO
            // and skip the .notConfigured contract this test asserts.
            resolveClientID: { _ in nil })
        do {
            try await store.connect(.google)
            XCTFail("expected notConfigured")
        } catch let error as ConnectorError {
            XCTAssertEqual(error, .notConfigured(.google))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testStatusReportsNotConnectedAndNotConfigured() async {
        let store = ConnectorStore(
            tokenStore: ConnectorTokenStore(read: { _ in nil }, write: { _, _ in }, remove: { _ in }),
            authorize: { _, _ in
                OAuth2.TokenResponse(accessToken: "", refreshToken: nil, expiresIn: 0, scopes: [], tokenType: "Bearer")
            })
        let statuses = await store.connectors()
        XCTAssertEqual(statuses.count, ConnectorID.allCases.count)
        let google = statuses.first { $0.id == .google }
        XCTAssertEqual(google?.isConnected, false)
    }

    func testExpiredTokenWithoutRefreshIsNotConnectedAndIsClearedOnUse() async throws {
        let tokens = memoryTokenStore()
        try tokens.save(ConnectorTokens(accessToken: "expired", refreshToken: nil,
                                        expiry: .distantPast, scopes: []), for: .google)
        let store = ConnectorStore(tokenStore: tokens,
                                   resolveClientID: { _ in "client-id" })

        let status = await store.status(.google)
        XCTAssertFalse(status.isConnected)

        let accessToken = await store.validAccessToken(.google)
        XCTAssertNil(accessToken)
        XCTAssertNil(tokens.load(.google))
    }

    func testExpiredTokenWithRefreshRemainsConnected() async throws {
        let tokens = memoryTokenStore()
        try tokens.save(ConnectorTokens(accessToken: "expired", refreshToken: "renewable",
                                        expiry: .distantPast, scopes: []), for: .google)
        let store = ConnectorStore(tokenStore: tokens,
                                   resolveClientID: { _ in "client-id" })

        let status = await store.status(.google)
        XCTAssertTrue(status.isConnected)
    }

    func testTerminalRefreshFailureClearsUnusableCredential() async throws {
        let tokens = memoryTokenStore()
        try tokens.save(ConnectorTokens(accessToken: "expired", refreshToken: "revoked",
                                        expiry: .distantPast, scopes: []), for: .google)
        let store = ConnectorStore(
            tokenStore: tokens,
            refresh: { _, _, _ in throw OAuth2.OAuth2Error.tokenExchangeFailed(400) },
            resolveClientID: { _ in "client-id" })

        let accessToken = await store.validAccessToken(.google)
        let status = await store.status(.google)

        XCTAssertNil(accessToken)
        XCTAssertNil(tokens.load(.google))
        XCTAssertFalse(status.isConnected)
    }

    func testTransientRefreshFailureRetainsRenewableCredential() async throws {
        let tokens = memoryTokenStore()
        try tokens.save(ConnectorTokens(accessToken: "expired", refreshToken: "retry-later",
                                        expiry: .distantPast, scopes: []), for: .google)
        let store = ConnectorStore(
            tokenStore: tokens,
            refresh: { _, _, _ in throw OAuth2.OAuth2Error.tokenExchangeFailed(503) },
            resolveClientID: { _ in "client-id" })

        let accessToken = await store.validAccessToken(.google)
        let status = await store.status(.google)

        XCTAssertNil(accessToken)
        XCTAssertNotNil(tokens.load(.google))
        XCTAssertTrue(status.isConnected)
    }

    func testConnectorStatusToolNeverCrashesUnconfigured() async throws {
        let store = ConnectorStore(
            tokenStore: ConnectorTokenStore(read: { _ in nil }, write: { _, _ in }, remove: { _ in }),
            authorize: { _, _ in
                OAuth2.TokenResponse(accessToken: "", refreshToken: nil, expiresIn: 0, scopes: [], tokenType: "Bearer")
            })
        let tool = ConnectorStatusTool(store: store)
        let result = try await tool.run(input: [:])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("Google"))
        XCTAssertTrue(result.output.contains("Notion"))
        XCTAssertTrue(result.output.contains("Slack"))
    }
}
