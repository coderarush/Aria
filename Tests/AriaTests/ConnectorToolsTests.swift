import XCTest
@testable import Aria

// MARK: - Pure display formatting (Gmail / Calendar JSON → tool text)

final class GoogleDisplayFormatTests: XCTestCase {

    func testFormatsGmailSummariesIntoDisplayBlock() {
        let messages = [
            GoogleConnector.GmailMessageSummary(
                id: "m1", from: "alice@example.com", subject: "Launch plan",
                snippet: "Here is the plan for next week"),
            GoogleConnector.GmailMessageSummary(
                id: "m2", from: "bob@example.com", subject: "Lunch?",
                snippet: "Free at noon?")
        ]
        let out = GoogleConnector.formatGmail(messages)
        XCTAssertTrue(out.hasPrefix("Recent Gmail:"))
        XCTAssertTrue(out.contains("Launch plan — from alice@example.com"))
        XCTAssertTrue(out.contains("Here is the plan for next week"))
        XCTAssertTrue(out.contains("Lunch? — from bob@example.com"))
    }

    func testGmailParsesThenFormatsFromRawJSON() throws {
        // Parse a real Gmail metadata response, then render it — end-to-end pure.
        let json = """
        {"id":"abc","snippet":"ping me back",
         "payload":{"headers":[{"name":"From","value":"carol@x.com"},
                                {"name":"Subject","value":"Quick question"}]}}
        """
        let msg = try XCTUnwrap(GoogleConnector.parseGmailMessage(Data(json.utf8)))
        let out = GoogleConnector.formatGmail([msg])
        XCTAssertTrue(out.contains("Quick question — from carol@x.com"))
        XCTAssertTrue(out.contains("ping me back"))
    }

    func testEmptyGmailGivesCleanMessage() {
        XCTAssertEqual(GoogleConnector.formatGmail([]), "No recent Gmail messages found.")
    }

    func testGmailMissingFieldsGetPlaceholders() {
        let msg = GoogleConnector.GmailMessageSummary(id: "m", from: "", subject: "", snippet: "")
        let out = GoogleConnector.formatGmail([msg])
        XCTAssertTrue(out.contains("(no subject)"))
        XCTAssertTrue(out.contains("(unknown sender)"))
    }

    func testFormatsCalendarEventsIntoDisplayBlock() {
        let events = [
            GoogleConnector.CalendarEvent(summary: "Standup", start: "2026-06-15T09:00:00Z"),
            GoogleConnector.CalendarEvent(summary: "1:1", start: "2026-06-16T14:00:00Z")
        ]
        let out = GoogleConnector.formatEvents(events)
        XCTAssertTrue(out.hasPrefix("Upcoming Google Calendar events:"))
        XCTAssertTrue(out.contains("2026-06-15T09:00:00Z — Standup"))
        XCTAssertTrue(out.contains("2026-06-16T14:00:00Z — 1:1"))
    }

    func testCalendarParsesThenFormatsFromRawJSON() {
        let json = """
        {"items":[{"summary":"Review","start":{"dateTime":"2026-06-15T10:00:00Z"}},
                  {"summary":"Holiday","start":{"date":"2026-06-19"}}]}
        """
        let events = GoogleConnector.parseCalendarEvents(Data(json.utf8))
        let out = GoogleConnector.formatEvents(events)
        XCTAssertTrue(out.contains("2026-06-15T10:00:00Z — Review"))
        XCTAssertTrue(out.contains("2026-06-19 — Holiday"))
    }

    func testEmptyCalendarGivesCleanMessage() {
        XCTAssertEqual(GoogleConnector.formatEvents([]),
                       "No upcoming Google Calendar events.")
    }
}

// MARK: - Not-connected tool behavior (no network, no token)

final class ConnectorToolNotConnectedTests: XCTestCase {

    /// A ConnectorStore backed by an empty token store → validAccessToken == nil.
    private func emptyStore() -> ConnectorStore {
        ConnectorStore(
            tokenStore: ConnectorTokenStore(read: { _ in nil }, write: { _, _ in }, remove: { _ in }),
            authorize: { _, _ in
                OAuth2.TokenResponse(accessToken: "", refreshToken: nil, expiresIn: 0,
                                     scopes: [], tokenType: "Bearer")
            })
    }

    func testGmailToolNotConnectedReturnsCleanMessage() async throws {
        let tool = GmailRecentTool(store: emptyStore())
        let result = try await tool.run(input: [:])
        XCTAssertTrue(result.success)  // clean message, not a failure/crash
        XCTAssertTrue(result.output.lowercased().contains("connect"))
        XCTAssertTrue(result.output.contains("Gmail"))
    }

    func testGmailToolNotConnectedIgnoresQuery() async throws {
        let tool = GmailRecentTool(store: emptyStore())
        let result = try await tool.run(input: ["query": "from:boss"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("connect"))
    }

    func testGcalToolNotConnectedReturnsCleanMessage() async throws {
        let tool = GcalUpcomingTool(store: emptyStore())
        let result = try await tool.run(input: [:])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("connect"))
        XCTAssertTrue(result.output.contains("Calendar"))
    }
}

// MARK: - client_secret in token exchange / refresh

final class OAuth2ClientSecretTests: XCTestCase {

    func testTokenExchangeIncludesSecretWhenGiven() {
        let body = OAuth2.tokenExchangeBody(
            code: "CODE", clientID: "CID", redirectURI: "http://127.0.0.1/cb",
            verifier: "VER", clientSecret: "SHHH")
        XCTAssertTrue(body.contains("client_secret=SHHH"))
        XCTAssertTrue(body.contains("client_id=CID"))
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
    }

    func testTokenExchangeOmitsSecretWhenNil() {
        // Google's PKCE-only path: byte-for-byte unchanged from the no-secret form.
        let withNil = OAuth2.tokenExchangeBody(
            code: "CODE", clientID: "CID", redirectURI: "http://127.0.0.1/cb",
            verifier: "VER", clientSecret: nil)
        let legacy = OAuth2.tokenExchangeBody(
            code: "CODE", clientID: "CID", redirectURI: "http://127.0.0.1/cb",
            verifier: "VER")  // default param
        XCTAssertFalse(withNil.contains("client_secret"))
        XCTAssertEqual(withNil, legacy)
    }

    func testTokenExchangeOmitsSecretWhenEmpty() {
        let body = OAuth2.tokenExchangeBody(
            code: "CODE", clientID: "CID", redirectURI: "http://127.0.0.1/cb",
            verifier: "VER", clientSecret: "")
        XCTAssertFalse(body.contains("client_secret"))
    }

    func testRefreshIncludesSecretWhenGiven() {
        let body = OAuth2.refreshBody(refreshToken: "RT", clientID: "CID", clientSecret: "SHHH")
        XCTAssertTrue(body.contains("client_secret=SHHH"))
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
    }

    func testRefreshOmitsSecretWhenNil() {
        let withNil = OAuth2.refreshBody(refreshToken: "RT", clientID: "CID", clientSecret: nil)
        let legacy = OAuth2.refreshBody(refreshToken: "RT", clientID: "CID")
        XCTAssertFalse(withNil.contains("client_secret"))
        XCTAssertEqual(withNil, legacy)
    }
}

// MARK: - Provider secret resolution (who supplies a secret)

final class ConnectorSecretResolutionTests: XCTestCase {

    func testGoogleNeverResolvesASecret() {
        // PKCE-only: even if a secret somehow sat in the Keychain, it is not used.
        let google = GoogleConnector()
        XCTAssertFalse(google.usesClientSecret)
        XCTAssertNil(google.resolvedClientSecret(keychainRead: { _ in "LEAKED" }))
    }

    func testNotionResolvesStoredSecret() {
        let notion = NotionConnector()
        XCTAssertTrue(notion.usesClientSecret)
        let secret = notion.resolvedClientSecret(keychainRead: { account in
            account == notion.clientSecretKeychainAccount ? "notion-secret" : nil
        })
        XCTAssertEqual(secret, "notion-secret")
    }

    func testSlackResolvesStoredSecret() {
        let slack = SlackConnector()
        XCTAssertTrue(slack.usesClientSecret)
        let secret = slack.resolvedClientSecret(keychainRead: { _ in "slack-secret" })
        XCTAssertEqual(secret, "slack-secret")
    }

    func testBlankSecretTreatedAsNil() {
        let notion = NotionConnector()
        XCTAssertNil(notion.resolvedClientSecret(keychainRead: { _ in "   " }))
    }

    func testAuthConfigThreadsSecretForConfidentialProviderOnly() {
        // Notion's config carries the secret; Google's does not, even when a value
        // is present under the Google secret key.
        let notion = NotionConnector()
        let notionConfig = OAuth2.AuthConfig(
            clientID: "CID", clientSecret: notion.resolvedClientSecret(keychainRead: { _ in "S" }),
            authEndpoint: notion.authEndpoint, tokenEndpoint: notion.tokenEndpoint,
            scopes: notion.scopes, extraAuthParameters: notion.extraAuthParameters)
        XCTAssertEqual(notionConfig.clientSecret, "S")

        let google = GoogleConnector()
        let googleConfig = OAuth2.AuthConfig(
            clientID: "CID", clientSecret: google.resolvedClientSecret(keychainRead: { _ in "S" }),
            authEndpoint: google.authEndpoint, tokenEndpoint: google.tokenEndpoint,
            scopes: google.scopes, extraAuthParameters: google.extraAuthParameters)
        XCTAssertNil(googleConfig.clientSecret)
    }
}
