# Operational Readiness — Implementation Plan

> **Goal:** Let the Mac-native home surface show whether Aria can actually hear,
> see, control apps, and reach connected accounts before the user starts a task.

## Design

The app already detects microphone, speech, Accessibility, Screen Recording,
and OAuth state independently, but the user must discover them through separate
settings and error messages. Add a compact, local-only readiness snapshot that
combines those signals without prompting for access or exposing account secrets.

- `OperationalReadiness` holds primitive capability state and builds pure,
  testable presentation rows.
- The live reader samples only public, non-prompting checks: Accessibility trust,
  `CGPreflightScreenCaptureAccess`, existing microphone/speech status, and the
  count of linked connector accounts.
- The Home model refreshes the snapshot alongside runtime state.
- A native `Capabilities` card uses semantic color and SF Symbols. It offers
  narrow recovery affordances: open Settings only when access is missing and
  navigate to Connectors only when no accounts are linked.

Screen Recording remains optional: vision tools tell the user when it is needed,
but the home card states its availability upfront. No background recording, token
inspection, OAuth refresh, or permission prompt is performed during refresh.

## Tasks

### 1. Model and test capability readiness

**Files:**
- Add: `Sources/Aria/Application/Runtime/OperationalReadiness.swift`
- Modify: `Sources/Aria/Permissions/Policy/PermissionsManager.swift`
- Add: `Tests/AriaTests/OperationalReadinessTests.swift`

1. Write failing pure tests for ready, missing-access, and unlinked-account rows.
2. Make permission status equatable/sendable; add the read-only snapshot and
   pure presentation mapper.
3. Run `swift test --filter OperationalReadinessTests`.

### 2. Wire the Home view model and native card

**Files:**
- Modify: `Sources/Aria/UI/Desktop/AppWindowModel.swift`
- Modify: `Sources/Aria/UI/Desktop/AppWindowPanes.swift`
- Modify: `Tests/AriaTests/AppWindowModelTests.swift`

1. Add failing view-model formatting tests for the readiness rows.
2. Refresh the snapshot with existing Home runtime data.
3. Add a quiet, responsive card with Settings and Connectors recovery actions.
4. Run focused tests and visually inspect the isolated app.

### 3. Full verification

1. Run `git diff --check` and inspect the diff.
2. Run focused tests, then `make test`.
3. Run `make verify-release && make release && codesign --verify --deep --strict .build/Aria.app`.
