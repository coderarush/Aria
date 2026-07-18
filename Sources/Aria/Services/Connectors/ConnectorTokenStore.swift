import Foundation

/// A persisted OAuth token bundle for one provider. Stored as JSON in a single
/// Keychain item per provider — access + refresh tokens never touch disk in
/// plaintext.
struct ConnectorTokens: Sendable, Equatable, Codable {
    var accessToken: String
    var refreshToken: String?
    /// Absolute wall-clock expiry of the access token.
    var expiry: Date
    var scopes: [String]

    /// Build a token bundle from an OAuth2 response, anchoring expiry to now.
    /// `previousRefreshToken` is retained when the response omits a new one
    /// (Google omits `refresh_token` on refreshes).
    init(from response: OAuth2.TokenResponse,
         previousRefreshToken: String? = nil,
         now: Date = Date()) {
        self.accessToken = response.accessToken
        self.refreshToken = response.refreshToken ?? previousRefreshToken
        self.expiry = now.addingTimeInterval(response.expiresIn)
        self.scopes = response.scopes
    }

    init(accessToken: String, refreshToken: String?, expiry: Date, scopes: [String]) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiry = expiry
        self.scopes = scopes
    }

    /// True when the access token is at/near expiry. A 60s skew means we refresh
    /// just before a request would fail rather than after.
    func isExpired(now: Date = Date(), skew: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(skew) >= expiry
    }

    /// Whether Aria can use this credential now or renew it automatically.
    /// An expired token with no refresh token is a known-unrecoverable state:
    /// keeping it in Keychain must not make the assistant claim the account is
    /// connected.
    func isUsable(now: Date = Date()) -> Bool {
        !isExpired(now: now) || refreshToken != nil
    }
}

/// Reads/writes `ConnectorTokens` keyed by provider. Backed by the Keychain via
/// an injectable closure pair so tests can use an in-memory store without
/// touching `securityd` (which can park on ACL prompts — see KeychainManager).
struct ConnectorTokenStore: Sendable {
    /// account key → JSON string. Returns nil when absent.
    let read: @Sendable (String) -> String?
    /// account key, JSON string. Throws on backend failure.
    let write: @Sendable (String, String) throws -> Void
    /// account key. Idempotent.
    let remove: @Sendable (String) -> Void

    /// The production store: tokens live in the macOS Keychain.
    static let keychain = ConnectorTokenStore(
        read: { KeychainManager.read(account: $0) },
        write: { account, value in try KeychainManager.save(value, account: account) },
        remove: { _ = KeychainManager.delete(account: $0) }
    )

    private static func account(for id: ConnectorID) -> String {
        "connector_tokens_\(id.rawValue)"
    }

    func load(_ id: ConnectorID) -> ConnectorTokens? {
        guard let json = read(Self.account(for: id)),
              let data = json.data(using: .utf8),
              let tokens = try? JSONDecoder().decode(ConnectorTokens.self, from: data)
        else { return nil }
        return tokens
    }

    func save(_ tokens: ConnectorTokens, for id: ConnectorID) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(tokens)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try write(Self.account(for: id), json)
    }

    func delete(_ id: ConnectorID) {
        remove(Self.account(for: id))
    }

    func isConnected(_ id: ConnectorID) -> Bool {
        load(id)?.isUsable() == true
    }
}
