# Local Work Capacity Gate Plan

**Goal:** Enforce the adaptive runtime's local-concurrency ceiling across all
Ollama work, preserving Mac responsiveness under power and thermal pressure.

## Scope

- Add an actor-isolated, shared non-queuing gate for local-model work.
- Admit at most the runtime recommendation's current limit. A busy gate falls
  back through Aria's existing cloud path; it does not queue work or block the
  interface.
- Apply the gate to local planning, streaming chat, and background model warming.
- Ensure every acquired slot is released on success, failure, cancellation, or
  stream completion.

## Acceptance checks

1. The gate admits only the configured number of concurrent requests and
   admits a later request after release.
2. A planning request returns its normal cloud-fallback signal (`nil`) while
   the one permitted slot is held.
3. Full tests, release validation, clean whitespace, and deep signature checks
   pass.
