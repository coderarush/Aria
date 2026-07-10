# Aria Hosted OAuth Relay — Design

> Status: DESIGN (infra not yet deployed). Decision locked: build the relay so a
> non-technical user connects Gmail/Calendar/Notion/Slack WITHOUT creating their
> own Google Cloud / developer project. BYO-client-ID stays as the dev/fallback path.

## The problem

Native macOS OAuth can't ship a client secret (it's extractable from the app), so
today each user must register their OWN OAuth client in the provider's console and
paste the client ID (and, for Notion/Slack, a secret) into Settings → Connectors.
That's fine for developers; it's a wall for normal users. The relay removes that
wall by holding ONE registered client per provider and brokering the exchange.

## Architecture

```
 Aria.app (native)                 Relay (Aria-operated)            Provider (Google/…)
 ─────────────────                 ────────────────────            ────────────────────
 1. PKCE verifier/challenge ──────────────────────────────────────────────────────────►
 2. open browser → relay /authorize?provider=google&challenge=…&state=…
                                   3. redirect to provider consent (relay's client_id,
                                      relay's redirect_uri, the user's PKCE challenge) ─►
                                   4. provider → relay /callback?code=… (user consented)
 5. loopback ◄── relay 302 to http://127.0.0.1:<port>/callback?relay_session=…
 6. POST relay /token {relay_session, verifier} ─►
                                   7. relay exchanges code+verifier+client_secret with
                                      provider, returns {access,refresh,expiry,scopes} ─►
 8. store tokens in Keychain (as today)
 9. refresh: POST relay /token {refresh_token} → relay refreshes with the secret
```

Key properties:
- **PKCE end-to-end.** The relay never sees the user's `code_verifier` until the
  token POST, and the app generates it — so a passive relay can't mint tokens.
- **Relay holds the client secret, not user tokens.** The exchange is pass-through;
  the relay returns tokens to the app and does NOT persist them. User tokens live
  only in the app's Keychain (unchanged from today).
- **Per-provider registered client.** Aria registers one OAuth client per provider
  (Google/Notion/Slack) with the relay's redirect URI. Users consent to "Aria",
  no project setup.
- **Scopes** are the same write scopes already in `GoogleConnector.scopes`.

## Client integration (the code change, when we build it)

A small switch in the connector layer — minimal, additive:
- Add `ConnectorMode` { `.bringYourOwn` (current default), `.relay` }, read from a
  setting (`app.connectorMode`, default `.bringYourOwn` until relay infra is live).
- `OAuth2.AuthConfig` gains `authorizationURL`/`tokenURL` that point at the relay
  (`https://relay.aria.app/authorize`, `/token`) in `.relay` mode, or the provider
  endpoints in `.bringYourOwn` (today's behavior, unchanged).
- In `.relay` mode the app sends NO client secret (the relay owns it); in
  `.bringYourOwn` it threads the Keychain secret (today's path — already built).
- `ConnectorStore.connect`/`refresh` are otherwise unchanged — they already speak
  the `{access,refresh,expiry,scopes}` shape the relay returns.
- Settings → Connectors: "Connect" just works in `.relay` mode (no client-ID
  sheet); the existing client-ID sheet stays available under an "Advanced /
  bring your own" disclosure.

This keeps the proven PKCE + Keychain client code; only the endpoint + secret
handling branch on mode.

## Relay service (infra — needs deployment, out of scope for the app build)

- Tiny stateless service (e.g. a single edge function / small server). Endpoints:
  `/authorize` (redirect to provider), `/callback` (receive provider code, 302 to
  the app's loopback with a short-lived `relay_session`), `/token` (exchange/refresh
  using the stored client secret).
- Secrets: provider client secrets in the host's secret manager; never logged.
- State: a short-TTL map of `relay_session → {provider, code}` (seconds), then
  discarded. No user tokens, no long-term storage.
- Rate-limit + abuse protection on `/token`.
- Privacy: the relay observes the OAuth `code` transiently for the exchange; design
  doc + privacy copy should state tokens are returned to the device and not stored.

## Decision / open items for the user (infra-side, not code)

1. Where to host the relay (Vercel edge fn / Cloudflare Worker / small VPS).
2. Register the OAuth apps (Google/Notion/Slack) under an Aria-owned account with
   the relay redirect URI; complete Google's verification for sensitive scopes
   (gmail.send etc. require Google app verification — a real review process).
3. Domain for the relay (`relay.aria.app`).

Until the relay is deployed, the app stays on the working `.bringYourOwn`
client-ID path; flipping the default to `.relay` is a one-line change once the
service is live.
