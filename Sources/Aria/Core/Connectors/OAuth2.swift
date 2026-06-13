import Foundation
import CryptoKit
import Network
#if canImport(AppKit)
import AppKit
#endif

/// Reusable OAuth2 Authorization Code + PKCE flow for native macOS apps.
///
/// Native apps cannot keep a client secret, so we use PKCE (RFC 7636) with the
/// loopback-redirect pattern (RFC 8252): we spin up a tiny HTTP listener on
/// `http://127.0.0.1:<ephemeral-port>/callback`, open the system browser to the
/// provider's consent screen, and capture the `code` from the redirect.
///
/// The pure, deterministic pieces — PKCE challenge derivation, auth-URL
/// construction, and token-response parsing — are split out as static helpers so
/// they can be unit-tested without touching the network or the browser. The live
/// network/browser parts (`authorize`) are kept thin and are not unit-tested.
enum OAuth2 {

    // MARK: - Errors

    enum OAuth2Error: Error, Equatable {
        case invalidAuthEndpoint
        case invalidTokenEndpoint
        case browserOpenFailed
        case listenerFailed(String)
        case stateMismatch
        case authorizationDenied(String)
        case missingCode
        case tokenExchangeFailed(Int)
        case malformedTokenResponse
        case timedOut
    }

    // MARK: - PKCE (pure / testable)

    /// A PKCE pair: a high-entropy `verifier` kept on the client and the derived
    /// `challenge` (+ method) sent on the authorization request.
    struct PKCE: Sendable, Equatable {
        let verifier: String
        let challenge: String
        let method: String  // always "S256"
    }

    /// Generate a fresh PKCE pair with a cryptographically random verifier.
    static func makePKCE() -> PKCE {
        let verifier = randomCodeVerifier()
        return PKCE(verifier: verifier,
                    challenge: codeChallengeS256(for: verifier),
                    method: "S256")
    }

    /// RFC 7636 §4.1: 43–128 chars from the unreserved set. We emit a 43-char
    /// url-safe base64 string derived from 32 random bytes.
    static func randomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        return base64URLEncode(Data(bytes))
    }

    /// RFC 7636 §4.2: `BASE64URL(SHA256(ASCII(verifier)))`, no padding.
    static func codeChallengeS256(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    /// URL-safe base64 with `+`→`-`, `/`→`_`, and trailing `=` padding stripped.
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Auth URL (pure / testable)

    /// Build the authorization-request URL the browser is opened to.
    /// Returns nil only if `authEndpoint` is not a valid URL.
    static func buildAuthorizationURL(
        authEndpoint: String,
        clientID: String,
        redirectURI: String,
        scopes: [String],
        challenge: String,
        challengeMethod: String = "S256",
        state: String,
        extraParameters: [String: String] = [:]
    ) -> URL? {
        guard var components = URLComponents(string: authEndpoint),
              components.scheme != nil, components.host != nil else { return nil }
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: challengeMethod),
            URLQueryItem(name: "state", value: state)
        ]
        for (k, v) in extraParameters.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: k, value: v))
        }
        components.queryItems = items
        return components.url
    }

    // MARK: - Token-response parsing (pure / testable)

    /// A normalized OAuth2 token response. `refreshToken` is optional because
    /// providers omit it on refreshes (and sometimes on re-consent).
    struct TokenResponse: Sendable, Equatable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval   // seconds until expiry
        let scopes: [String]
        let tokenType: String
    }

    /// Parse a provider token-endpoint JSON body. Returns nil for any body that
    /// lacks an `access_token`. A missing `refresh_token` is preserved as nil.
    static func parseTokenResponse(_ data: Data) -> TokenResponse? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = obj["access_token"] as? String,
              !accessToken.isEmpty else { return nil }

        let refresh = (obj["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        // `expires_in` may arrive as a number or a numeric string.
        let expires: TimeInterval
        if let n = obj["expires_in"] as? Double { expires = n }
        else if let i = obj["expires_in"] as? Int { expires = TimeInterval(i) }
        else if let s = obj["expires_in"] as? String, let d = Double(s) { expires = d }
        else { expires = 3600 }  // conservative default

        let scopeString = (obj["scope"] as? String) ?? ""
        let scopes = scopeString.split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init).filter { !$0.isEmpty }
        let tokenType = (obj["token_type"] as? String) ?? "Bearer"

        return TokenResponse(accessToken: accessToken,
                             refreshToken: refresh,
                             expiresIn: expires,
                             scopes: scopes,
                             tokenType: tokenType)
    }

    /// Extract the `code` (or an `error`) from a captured redirect URL/query.
    /// Returns `.success(code)` or `.failure(OAuth2Error)`. Validates `state`.
    static func parseRedirect(query: String, expectedState: String)
        -> Result<String, OAuth2Error> {
        var comps = URLComponents()
        comps.query = query
        let items = comps.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let err = value("error") {
            return .failure(.authorizationDenied(err))
        }
        guard let state = value("state"), state == expectedState else {
            return .failure(.stateMismatch)
        }
        guard let code = value("code"), !code.isEmpty else {
            return .failure(.missingCode)
        }
        return .success(code)
    }

    /// Build the form body for the authorization-code → token exchange.
    static func tokenExchangeBody(
        code: String, clientID: String, redirectURI: String, verifier: String
    ) -> String {
        formEncode([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": verifier
        ])
    }

    /// Build the form body for a refresh-token grant.
    static func refreshBody(refreshToken: String, clientID: String) -> String {
        formEncode([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ])
    }

    static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return params.sorted { $0.key < $1.key }.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
    }

    /// Generate an opaque anti-CSRF `state` value.
    static func makeState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        return base64URLEncode(Data(bytes))
    }

    // MARK: - Live flow (thin / untested)

    /// Configuration for one authorization run.
    struct AuthConfig: Sendable {
        let clientID: String
        let authEndpoint: String
        let tokenEndpoint: String
        let scopes: [String]
        /// Extra auth-request params (Google needs `access_type=offline` &
        /// `prompt=consent` to reliably return a refresh_token).
        let extraAuthParameters: [String: String]
    }

    /// Run the full interactive PKCE flow: start a loopback listener, open the
    /// browser, capture the code, and exchange it for tokens. Thin wrapper over
    /// the tested helpers; the network/browser pieces are intentionally minimal.
    static func authorize(config: AuthConfig,
                          session: URLSession = .shared,
                          timeout: TimeInterval = 300) async throws -> TokenResponse {
        let pkce = makePKCE()
        let state = makeState()

        let listener = try LoopbackListener()
        defer { listener.stop() }
        let redirectURI = "http://127.0.0.1:\(listener.port)/callback"

        guard let url = buildAuthorizationURL(
            authEndpoint: config.authEndpoint,
            clientID: config.clientID,
            redirectURI: redirectURI,
            scopes: config.scopes,
            challenge: pkce.challenge,
            challengeMethod: pkce.method,
            state: state,
            extraParameters: config.extraAuthParameters
        ) else { throw OAuth2Error.invalidAuthEndpoint }

        #if canImport(AppKit)
        guard NSWorkspace.shared.open(url) else { throw OAuth2Error.browserOpenFailed }
        #endif

        let query = try await listener.waitForCallback(timeout: timeout)
        let code: String
        switch parseRedirect(query: query, expectedState: state) {
        case .success(let c): code = c
        case .failure(let e): throw e
        }

        return try await exchangeCode(code: code,
                                      redirectURI: redirectURI,
                                      verifier: pkce.verifier,
                                      config: config,
                                      session: session)
    }

    /// Exchange an authorization code for tokens against the token endpoint.
    static func exchangeCode(code: String, redirectURI: String, verifier: String,
                             config: AuthConfig, session: URLSession) async throws
        -> TokenResponse {
        guard let url = URL(string: config.tokenEndpoint) else {
            throw OAuth2Error.invalidTokenEndpoint
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(tokenExchangeBody(code: code, clientID: config.clientID,
                                              redirectURI: redirectURI,
                                              verifier: verifier).utf8)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OAuth2Error.tokenExchangeFailed(status) }
        guard let token = parseTokenResponse(data) else {
            throw OAuth2Error.malformedTokenResponse
        }
        return token
    }

    /// Refresh an access token. Google may not return a new `refresh_token`, so
    /// callers should keep the old one when the response omits it.
    static func refresh(refreshToken: String, config: AuthConfig,
                        session: URLSession = .shared) async throws -> TokenResponse {
        guard let url = URL(string: config.tokenEndpoint) else {
            throw OAuth2Error.invalidTokenEndpoint
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(refreshBody(refreshToken: refreshToken,
                                        clientID: config.clientID).utf8)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OAuth2Error.tokenExchangeFailed(status) }
        guard let token = parseTokenResponse(data) else {
            throw OAuth2Error.malformedTokenResponse
        }
        return token
    }
}

/// A minimal one-shot loopback HTTP listener (RFC 8252 redirect capture).
/// Binds to an ephemeral 127.0.0.1 port, accepts a single GET, returns the raw
/// query string, and replies with a tiny "you can close this tab" page.
/// Thin and untested — the parsing it feeds is covered by `parseRedirect`.
final class LoopbackListener: @unchecked Sendable {
    private let listener: NWListener
    let port: UInt16
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false

    init() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let l: NWListener
        do { l = try NWListener(using: params) }
        catch { throw OAuth2.OAuth2Error.listenerFailed("\(error)") }
        self.listener = l
        // Resolve the OS-assigned port. NWListener publishes it once started.
        let sem = DispatchSemaphore(value: 0)
        var resolved: UInt16 = 0
        l.stateUpdateHandler = { state in
            if case .ready = state, let p = l.port?.rawValue {
                resolved = p
                sem.signal()
            }
        }
        l.start(queue: .global())
        if sem.wait(timeout: .now() + 5) == .timedOut || resolved == 0 {
            l.cancel()
            throw OAuth2.OAuth2Error.listenerFailed("port not assigned")
        }
        self.port = resolved
    }

    /// Suspend until a redirect arrives (or `timeout` elapses), returning the
    /// raw query string from the request line.
    func waitForCallback(timeout: TimeInterval) async throws -> String {
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                lock.lock(); self.continuation = cont; lock.unlock()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.resume(.failure(OAuth2.OAuth2Error.timedOut))
                }
            }
        } onCancel: {
            self.resume(.failure(OAuth2.OAuth2Error.timedOut))
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            defer { conn.cancel() }
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
            // First line: "GET /callback?code=...&state=... HTTP/1.1"
            let firstLine = request.split(separator: "\r\n").first.map(String.init) ?? ""
            let parts = firstLine.split(separator: " ")
            var query = ""
            if parts.count >= 2, let q = parts[1].split(separator: "?", maxSplits: 1).dropFirst().first {
                query = String(q)
            }
            let body = "<html><body style=\"font-family:-apple-system;text-align:center;padding-top:4rem\">"
                + "<h2>Aria is connected.</h2><p>You can close this tab.</p></body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
                + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
            self.resume(.success(query))
        }
    }

    private func resume(_ result: Result<String, Error>) {
        lock.lock()
        guard !finished, let cont = continuation else { lock.unlock(); return }
        finished = true
        continuation = nil
        lock.unlock()
        cont.resume(with: result)
    }

    func stop() { listener.cancel() }
}
