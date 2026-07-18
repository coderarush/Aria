# Terminal Connector Refresh Repair Plan

**Goal:** Keep connector status truthful after a refresh token has been
revoked, without treating a temporary service problem as a disconnection.

## Scope

- Inject the refresh operation through `ConnectorStore` so authorization
  outcomes are deterministic in tests.
- Delete an expired credential only after terminal OAuth authorization errors
  (HTTP 400–403).
- Retain credentials for rate limits, server errors, malformed responses, and
  transport failures so Aria can retry later.

## Acceptance checks

1. A 400 refresh failure returns no access token, removes the stored credential,
   and makes the connector report disconnected.
2. A 503 refresh failure returns no access token but retains the credential and
   its renewable status.
3. Focused, full, release, signature, and whitespace checks pass.
