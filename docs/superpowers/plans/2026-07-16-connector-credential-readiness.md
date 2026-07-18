# Connector Credential Readiness Plan

**Goal:** Never present a connector as ready when its stored credential cannot
be used or renewed.

## Scope

- Treat an expired access token with no refresh token as disconnected in every
  `ConnectorStatus` snapshot.
- Remove that known-unrecoverable token when a caller asks for an access token.
- Keep expired tokens that have a refresh token connected: they can renew on
  demand and must not make the interface flicker into a false setup state.
- Keep transient refresh/network failures non-destructive.

## Acceptance checks

1. An expired token without a refresh token is not reported as connected.
2. Requesting a token for that state returns `nil` and removes the stale token.
3. An expired token with a refresh token remains reported as connected.
4. The complete test suite and signed release bundle pass.
