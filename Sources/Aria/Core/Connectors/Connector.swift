import Foundation

/// Identity of a third-party account Aria can connect to. The set is fixed
/// (Google, Notion, Slack); each case carries its OAuth endpoints and scopes.
enum ConnectorID: String, CaseIterable, Sendable, Codable {
    case google
    case notion
    case slack
}

/// Describes one OAuth-backed provider: the endpoints, scopes, and the
/// Keychain/UserDefaults keys where the user-supplied client ID lives.
///
/// No secrets are compiled in. The client ID is supplied by the user (each
/// install registers its own OAuth app) and read from the Keychain first, then
/// UserDefaults as a fallback. A missing client ID is a clean, surfaced state
/// (`isConfigured == false`) — never a crash.
protocol ConnectorProvider: Sendable {
    var id: ConnectorID { get }
    var displayName: String { get }
    var scopes: [String] { get }
    var authEndpoint: String { get }
    var tokenEndpoint: String { get }
    /// Extra auth-request parameters (e.g. Google's `access_type=offline`).
    var extraAuthParameters: [String: String] { get }
    /// The Keychain account key under which the user's client ID is stored.
    var clientIDKeychainAccount: String { get }
    /// The UserDefaults key checked if the Keychain has no client ID.
    var clientIDDefaultsKey: String { get }
}

extension ConnectorProvider {
    var extraAuthParameters: [String: String] { [:] }
    var clientIDKeychainAccount: String { "connector_\(id.rawValue)_client_id" }
    var clientIDDefaultsKey: String { "connector.\(id.rawValue).clientID" }

    /// Resolve the user-supplied OAuth client ID, or nil if not configured.
    /// Keychain wins; UserDefaults is the fallback for non-secret IDs that a
    /// user may have pasted into settings. Never throws, never crashes.
    func resolvedClientID(
        keychainRead: (String) -> String? = { KeychainManager.read(account: $0) },
        defaults: UserDefaults = .standard
    ) -> String? {
        if let k = keychainRead(clientIDKeychainAccount),
           !k.trimmingCharacters(in: .whitespaces).isEmpty {
            return k
        }
        if let d = defaults.string(forKey: clientIDDefaultsKey),
           !d.trimmingCharacters(in: .whitespaces).isEmpty {
            return d
        }
        return nil
    }

    var isConfigured: Bool { resolvedClientID() != nil }

    /// Build an `OAuth2.AuthConfig` from this provider + a resolved client ID.
    func authConfig(clientID: String) -> OAuth2.AuthConfig {
        OAuth2.AuthConfig(clientID: clientID,
                          authEndpoint: authEndpoint,
                          tokenEndpoint: tokenEndpoint,
                          scopes: scopes,
                          extraAuthParameters: extraAuthParameters)
    }
}

/// The registry of known providers, keyed by `ConnectorID`. Google is fully
/// implemented; Notion and Slack carry their real endpoints so they can be
/// wired up later without touching this file.
enum Connectors {
    static func provider(for id: ConnectorID) -> ConnectorProvider {
        switch id {
        case .google: return GoogleConnector()
        case .notion: return NotionConnector()
        case .slack:  return SlackConnector()
        }
    }

    static var all: [ConnectorProvider] { ConnectorID.allCases.map(provider) }
}

/// Notion endpoints (OAuth2). Scope set is implicit in Notion's integration
/// settings, so `scopes` is empty here. Endpoints kept accurate for later use.
struct NotionConnector: ConnectorProvider {
    let id: ConnectorID = .notion
    let displayName = "Notion"
    let scopes: [String] = []
    let authEndpoint = "https://api.notion.com/v1/oauth/authorize"
    let tokenEndpoint = "https://api.notion.com/v1/oauth/token"
    var extraAuthParameters: [String: String] { ["owner": "user"] }
}

/// Slack endpoints (OAuth v2). Read-oriented default scopes.
struct SlackConnector: ConnectorProvider {
    let id: ConnectorID = .slack
    let displayName = "Slack"
    let scopes = ["channels:read", "chat:write", "users:read"]
    let authEndpoint = "https://slack.com/oauth/v2/authorize"
    let tokenEndpoint = "https://slack.com/api/oauth.v2.access"
}
