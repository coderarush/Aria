import Foundation

/// The user-facing connection state of one provider. `Sendable` so it crosses
/// the actor boundary into the (future) UI cleanly.
struct ConnectorStatus: Sendable, Equatable, Identifiable {
    let id: ConnectorID
    let displayName: String
    /// The user has supplied an OAuth client ID for this provider.
    let isConfigured: Bool
    /// A credential is usable now or can be renewed automatically.
    let isConnected: Bool
    /// The granted scopes, when connected.
    let scopes: [String]
    /// Access-token expiry, when connected.
    let expiry: Date?
}

/// Errors surfaced to the UI from connection attempts.
enum ConnectorError: Error, Equatable {
    /// The user hasn't supplied an OAuth client ID for this provider yet.
    case notConfigured(ConnectorID)
}

/// The single entry point the UI uses to inspect and manage connections.
///
/// An `actor` so concurrent UI taps and background refreshes serialize against
/// one token store. The live OAuth flow (`connect`) opens the browser and runs
/// a loopback listener; everything else is local Keychain bookkeeping.
actor ConnectorStore {
    static let shared = ConnectorStore()

    private let tokenStore: ConnectorTokenStore
    private let session: URLSession
    /// Injectable so tests can avoid the real network/browser.
    private let authorizeImpl: @Sendable (OAuth2.AuthConfig, URLSession) async throws -> OAuth2.TokenResponse
    /// Injectable so refresh-failure handling is deterministic in tests.
    private let refreshImpl: @Sendable (String, OAuth2.AuthConfig, URLSession) async throws -> OAuth2.TokenResponse
    /// Injectable so tests can pin the "is a client ID configured?" answer without
    /// touching the real Keychain — otherwise a developer's stored client ID makes
    /// the BYO "not configured" contract non-hermetic (different result per machine).
    private let resolveClientID: @Sendable (any ConnectorProvider) -> String?

    init(tokenStore: ConnectorTokenStore = .keychain,
         session: URLSession = .shared,
         authorize: @escaping @Sendable (OAuth2.AuthConfig, URLSession) async throws -> OAuth2.TokenResponse =
            { config, session in try await OAuth2.authorize(config: config, session: session) },
         refresh: @escaping @Sendable (String, OAuth2.AuthConfig, URLSession) async throws -> OAuth2.TokenResponse =
            { token, config, session in try await OAuth2.refresh(refreshToken: token, config: config, session: session) },
         resolveClientID: @escaping @Sendable (any ConnectorProvider) -> String? = { $0.resolvedClientID() }) {
        self.tokenStore = tokenStore
        self.session = session
        self.authorizeImpl = authorize
        self.refreshImpl = refresh
        self.resolveClientID = resolveClientID
    }

    /// Snapshot of every known provider's status (config + connection).
    func connectors() -> [ConnectorStatus] {
        let mode = ConnectorMode.current()
        return Connectors.all.map { provider in
            let tokens = tokenStore.load(provider.id)
            return ConnectorStatus(
                id: provider.id,
                displayName: provider.displayName,
                isConfigured: provider.isConfigured(mode: mode),
                isConnected: tokens?.isUsable() == true,
                scopes: tokens?.scopes ?? [],
                expiry: tokens?.expiry
            )
        }
    }

    func status(_ id: ConnectorID) -> ConnectorStatus {
        let provider = Connectors.provider(for: id)
        let tokens = tokenStore.load(id)
        return ConnectorStatus(
            id: id,
            displayName: provider.displayName,
            isConfigured: provider.isConfigured(mode: ConnectorMode.current()),
            isConnected: tokens?.isUsable() == true,
            scopes: tokens?.scopes ?? [],
            expiry: tokens?.expiry
        )
    }

    func isConnected(_ id: ConnectorID) -> Bool {
        tokenStore.isConnected(id)
    }

    /// Run the interactive OAuth flow for a provider and store the result.
    /// Throws `.notConfigured` (cleanly) when no client ID is set.
    func connect(_ id: ConnectorID) async throws {
        let provider = Connectors.provider(for: id)
        let mode = ConnectorMode.current()
        // `.relay`: the relay supplies the client, so no user client ID is needed.
        //           `clientID` is ignored by the relay config builder.
        // `.bringYourOwn`: a user client ID is required (today's behavior).
        let clientID: String
        switch mode {
        case .relay:
            clientID = resolveClientID(provider) ?? ""
        case .bringYourOwn:
            guard let resolved = resolveClientID(provider) else {
                throw ConnectorError.notConfigured(id)
            }
            clientID = resolved
        }
        let config = provider.authConfig(clientID: clientID, mode: mode)
        let response = try await authorizeImpl(config, session)
        let tokens = ConnectorTokens(from: response)
        try tokenStore.save(tokens, for: id)
    }

    /// Forget a provider's tokens. Idempotent.
    func disconnect(_ id: ConnectorID) {
        tokenStore.delete(id)
    }

    /// Return a valid access token for `id`, refreshing if expired. Returns nil
    /// when not connected, not configured, or the refresh fails. Persists a
    /// refreshed token so the next call is cheap.
    func validAccessToken(_ id: ConnectorID) async -> String? {
        guard var tokens = tokenStore.load(id) else { return nil }
        guard tokens.isExpired() else { return tokens.accessToken }
        guard let refreshToken = tokens.refreshToken else {
            // The token can neither be used nor renewed. Forget it so every
            // later snapshot truthfully presents the account as disconnected.
            tokenStore.delete(id)
            return nil
        }
        let provider = Connectors.provider(for: id)
        let mode = ConnectorMode.current()
        // `.bringYourOwn` refreshes need the user client ID; `.relay` refreshes go
        // through the relay (which holds the client) and need no user client ID.
        let clientID: String
        switch mode {
        case .relay:
            clientID = resolveClientID(provider) ?? ""
        case .bringYourOwn:
            guard let resolved = resolveClientID(provider) else { return nil }
            clientID = resolved
        }
        do {
            let response = try await refreshImpl(refreshToken,
                                                 provider.authConfig(clientID: clientID, mode: mode),
                                                 session)
            tokens = ConnectorTokens(from: response, previousRefreshToken: refreshToken)
            try? tokenStore.save(tokens, for: id)
            return tokens.accessToken
        } catch {
            if Self.isTerminalRefreshFailure(error) {
                // A revoked/invalid authorization cannot become usable by retrying.
                // Clear it so Home, tools, and the model ask for reconnection honestly.
                tokenStore.delete(id)
            }
            Log.trace("connector \(id.rawValue): token refresh failed (\(error))")
            return nil
        }
    }

    private static func isTerminalRefreshFailure(_ error: Error) -> Bool {
        guard case let OAuth2.OAuth2Error.tokenExchangeFailed(status) = error else { return false }
        return (400...403).contains(status)
    }
}
