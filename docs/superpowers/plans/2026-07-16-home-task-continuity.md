# Home Task Continuity Plan

**Goal:** Make the Home surface show the one task Aria is actively working on
or can safely resume, without guessing from timestamps or exposing task data.

## Scope

- Mark a `TaskStore` snapshot as `running` only when it was saved by the current
  process; the same persisted snapshot is `resumable` after a relaunch.
- Convert that state into a privacy-safe Home summary: goal, completed/total
  steps, and next step summary only.
- Add a native material card with an explicit voice resume affordance. It does
  not start or mutate a task from the dashboard.

## Acceptance checks

1. The current store reports a newly saved snapshot as running.
2. A fresh store instance reading that same snapshot reports it as resumable.
3. Home summaries use clear labels for running and resuming, and omit raw
   input/output.
4. Focused, full, release, signature, and whitespace checks pass.
