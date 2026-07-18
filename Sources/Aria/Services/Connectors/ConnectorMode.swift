import Foundation

/// How Aria brokers the OAuth exchange for connected accounts.
///
/// - `.relay`: hosted mode. Token/authorization traffic goes through Aria's
///   hosted relay (`https://relay.aria.app`), which holds ONE registered OAuth
///   client per provider and the client secret. The user connects an account
///   with no developer-console setup and no pasted client ID — the relay supplies
///   the client. The app still generates the PKCE verifier locally and stores the
///   returned tokens in the Keychain exactly as in `.bringYourOwn`.
/// - `.bringYourOwn`: the default until the hosted relay is deployed. The user
///   registers their own OAuth app, pastes the client ID (and, for confidential
///   providers, the secret) into Settings, and the app talks directly to the
///   provider's endpoints.
///
/// The mode is a single UserDefaults setting (`app.connectorMode`); the Settings
/// toggle that writes it is built separately. This layer only reads it.
enum ConnectorMode: String, Sendable, Equatable, CaseIterable {
    case relay
    case bringYourOwn

    /// The UserDefaults key the mode is persisted under.
    static let defaultsKey = "app.connectorMode"

    /// The mode in effect, read from `defaults`. Defaults to `.bringYourOwn`
    /// when unset or when the stored string is unrecognized — pure, no side effects.
    static func current(defaults: UserDefaults = .standard) -> ConnectorMode {
        guard let raw = defaults.string(forKey: defaultsKey),
              let mode = ConnectorMode(rawValue: raw) else { return .bringYourOwn }
        return mode
    }
}

/// Pure builders for the hosted OAuth relay's endpoints.
///
/// The relay exposes `/authorize` (browser → provider consent, using the relay's
/// own client) and `/token` (code↔token + refresh, using the relay's secret). The
/// app passes the **provider id** and the **PKCE challenge** it generated — never a
/// user client ID and never a secret. See `docs/v11.1/OAUTH_RELAY_DESIGN.md`.
enum RelayConfig {
    /// The production relay base. Overridable via UserDefaults `app.connectorRelayBase`
    /// purely so tests (and a future staging flip) can retarget it; no trailing slash.
    static let defaultBase = "https://relay.aria.app"

    /// The UserDefaults key that overrides `defaultBase` (testing / staging).
    static let baseDefaultsKey = "app.connectorRelayBase"

    /// Resolve the relay base, honoring the UserDefaults override. Any trailing
    /// slashes are trimmed so URL joins stay clean.
    static func base(defaults: UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey: baseDefaultsKey)?
            .trimmingCharacters(in: .whitespaces)
        let chosen = (raw?.isEmpty == false ? raw! : defaultBase)
        return trimTrailingSlashes(chosen)
    }

    /// `<base>/authorize?provider=…&code_challenge=…&code_challenge_method=S256&state=…&redirect_uri=…`
    ///
    /// The relay maps `provider` → its registered client and redirect, then 302s to
    /// the provider's consent screen carrying the app's PKCE challenge. `redirect`
    /// is the app's loopback URL the relay ultimately bounces back to. Returns nil
    /// only if the base is not a valid URL.
    static func authorizeURL(provider: ConnectorID,
                             challenge: String,
                             state: String,
                             redirect: String,
                             challengeMethod: String = "S256",
                             defaults: UserDefaults = .standard) -> URL? {
        guard var components = URLComponents(string: base(defaults: defaults) + "/authorize"),
              components.scheme != nil, components.host != nil else { return nil }
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: challengeMethod),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: redirect)
        ]
        return components.url
    }

    /// `<base>/token` — the code↔token and refresh endpoint. Returns nil only if the
    /// base is not a valid URL.
    static func tokenURL(defaults: UserDefaults = .standard) -> URL? {
        URL(string: base(defaults: defaults) + "/token")
    }

    /// The string form of `tokenURL`, for stuffing into `AuthConfig.tokenEndpoint`.
    static func tokenEndpoint(defaults: UserDefaults = .standard) -> String {
        base(defaults: defaults) + "/token"
    }

    /// The string form of the relay `/authorize` base, for `AuthConfig.authEndpoint`.
    /// Per-run query params (challenge/state/redirect) are appended by the OAuth flow.
    static func authorizeEndpoint(defaults: UserDefaults = .standard) -> String {
        base(defaults: defaults) + "/authorize"
    }

    private static func trimTrailingSlashes(_ s: String) -> String {
        var out = s
        while out.hasSuffix("/") { out.removeLast() }
        return out
    }
}
