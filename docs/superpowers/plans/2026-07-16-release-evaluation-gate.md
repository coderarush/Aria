# Release Evaluation Gate Plan

**Goal:** Make deterministic assistant evaluations an explicit release gate,
with inspectable pass/fail output rather than an unused metric.

## Scope

- Derive a gate from `EvaluationSummary` using a completion threshold and
  required scenario names.
- Report missing or failed required scenarios in a deterministic string.
- Add a focused `make evaluate` target and make release run it before assembly.
- Keep the gate fully local: deterministic tools only, no model, account,
  network, or hardware dependency.

## Acceptance checks

1. A summary at the threshold with all required scenarios passing passes.
2. A failed or missing required scenario fails even when the aggregate rate is
   high enough.
3. `make evaluate`, full tests, release, signature, and whitespace checks pass.
