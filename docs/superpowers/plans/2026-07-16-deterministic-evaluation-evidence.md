# Deterministic Evaluation Evidence Plan

**Goal:** Turn Aria's existing local evaluation path into useful engineering
evidence: measured execution time plus an inspectable result for every
scenario.

## Scope

- Measure a coordinator run with an injectable wall clock, clamping a backwards
  clock adjustment to zero.
- Carry that measured duration into the evaluation summary.
- Preserve a compact outcome for every scenario: name, kind, final status,
  verification result, and duration.
- Keep evaluation local and deterministic; no telemetry, network calls, model
  inference, or release-server dependency is added.

## Acceptance checks

1. A fixture clock produces an exact coordinator duration.
2. A mixed pass/fail harness run reports the failed scenario by name and the
   exact average duration.
3. Existing summary fields keep their behavior.
4. Focused, full, release, signing, and whitespace checks pass.
