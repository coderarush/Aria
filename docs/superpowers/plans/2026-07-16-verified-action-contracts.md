# Verified Action Contracts — Implementation Plan

> **Goal:** Make deterministic Mac workflows report completion only after Aria can
> check the intended state, while retaining safe compatibility for existing plans.

## Design

`TaskStep` already carries a `PostCondition`, but generated plans cannot express
one, persisted plans lose it, and the current executor only checks tool text.
This pass turns that dormant type into an explicit, observable contract:

- support local, deterministic app-state checks (`appRunning` / `appNotRunning`)
  alongside the existing textual checks;
- keep the checker injectable and bounded, so unit tests never touch a live Mac
  and app launch/quit gets a short settling window in production;
- parse a strictly whitelisted optional `verify` object from planner JSON;
- preserve each condition across task resumption;
- re-check the same condition after recovery, preventing an alternative action
  from being marked done merely because it returned successfully;
- make Focus Mode use app-state contracts out of the box; and
- surface a compact confirmation in the completed step result.

No blind retries are added for click or type operations. Those actions remain
honest about a successful dispatch unless a future, target-specific AX condition
can verify their visual state without risking duplicate input.

## Tasks

### 1. Build the contract and verifier

**Files:**
- Modify: `Sources/Aria/Execution/Executor/PostCondition.swift`
- Modify: `Tests/AriaTests/PostConditionTests.swift`

1. Add failing tests for app name normalisation, success, failure, and a bounded
   verifier with injected app state.
2. Add `appRunning` and `appNotRunning` conditions, human-readable descriptions,
   and a `PostConditionVerifier` with a live `NSWorkspace` implementation.
3. Run `swift test --filter PostConditionTests`.

### 2. Carry conditions through planning and resumption

**Files:**
- Modify: `Sources/Aria/Planning/Planner/PlanParser.swift`
- Modify: `Sources/Aria/Planning/Planner/TaskPlan.swift`
- Modify: `Sources/Aria/Execution/Scheduler/TaskStore.swift`
- Modify: `Tests/AriaTests/PlanParserTests.swift`
- Modify: `Tests/AriaTests/TaskStoreTests.swift`

1. Add tests for the accepted `verify` JSON forms and condition round-trip.
2. Parse only known condition kinds; malformed or unknown forms remain `.none`.
3. Store an optional condition in persisted tasks so older task files stay decodable.
4. Run focused parser/store tests.

### 3. Enforce and expose verified effects in task execution

**Files:**
- Modify: `Sources/Aria/Execution/Executor/AutonomyEngine.swift`
- Modify: `Sources/Aria/Execution/Actions/FocusMode.swift`
- Modify: `Tests/AriaTests/FocusModeTests.swift`
- Add or modify: `Tests/AriaTests/AutonomyEngineTests.swift`

1. Add tests for Focus Mode's explicit app-state conditions and the execution
   helper's confirmed/failed formatting.
2. Inject the verifier into `AutonomyEngine`; evaluate it after every successful
   initial action and after recovery.
3. Convert an unmet explicit condition to an honest failure, so recovery runs;
   append a concise confirmation when it passes.
4. Give Focus Mode open/close steps their matching state contracts.
5. Run focused tests.

### 4. Full verification

1. Run `git diff --check`.
2. Run the focused suites, then `make test`.
3. Run `make verify-release && make release && codesign --verify --deep --strict .build/Aria.app`.
4. Inspect the final diff for accidental scope expansion.
