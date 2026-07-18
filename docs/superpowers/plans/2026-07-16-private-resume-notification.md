# Private Resume Notification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent restart notifications from exposing an unfinished task's goal while keeping the resume reminder actionable.

**Architecture:** Add a pure presentation mapper beside the persisted-task
model. The launch controller requests generic text from it and sends no task
goal to the system notifier. The existing Home card and confirmation remain
the detailed, opt-in path.

**Tech Stack:** Swift 6, XCTest, AppKit notification bridge.

## Global Constraints

- Keep task goal, step summary, raw input, and raw output out of system
  notification text.
- Preserve the existing `app.notifyResume` opt-out and the Home confirmation
  gate.
- Do not stage, commit, or modify unrelated user changes.

---

### Task 1: Generic resume-notification presentation

**Files:**
- Modify: `Sources/Aria/Execution/Scheduler/TaskStore.swift`
- Modify: `Tests/AriaTests/TaskStoreTests.swift`

**Interfaces:**
- Consumes: `PersistedTask.unfinishedCount: Int`
- Produces: `ResumeNotificationPresentation.body(remainingSteps: Int) -> String`
- Used by: `AriaController.offerResumeIfPending()`

- [ ] **Step 1: Write the failing test**

```swift
func testResumeNotificationDoesNotExposeTaskGoal() {
    let goal = "Send the confidential acquisition draft"
    let body = ResumeNotificationPresentation.body(remainingSteps: 2)
    XCTAssertEqual(body, "An unfinished task is ready to resume (2 steps left). Open Aria or say “resume” to continue.")
    XCTAssertFalse(body.localizedCaseInsensitiveContains(goal))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter TaskStoreTests/testResumeNotificationDoesNotExposeTaskGoal`

Expected: compilation failure because `ResumeNotificationPresentation` is not
defined.

- [ ] **Step 3: Add the minimal pure implementation**

```swift
enum ResumeNotificationPresentation {
    static func body(remainingSteps: Int) -> String {
        let count = max(remainingSteps, 0)
        let steps = count == 1 ? "1 step" : "\(count) steps"
        return "An unfinished task is ready to resume (\(steps) left). Open Aria or say “resume” to continue."
    }
}
```

- [ ] **Step 4: Run the focused tests**

Run: `swift test --filter TaskStoreTests`

Expected: all TaskStore tests pass.

### Task 2: Use private presentation at launch

**Files:**
- Modify: `Sources/Aria/Application/App/AriaController.swift:575-584`
- Test: `Tests/AriaTests/TaskStoreTests.swift`

**Interfaces:**
- Consumes: `ResumeNotificationPresentation.body(remainingSteps:)`
- Produces: generic `Notifier.notify(title: "Aria", body: ...)` call
- Preserves: `app.notifyResume` guard and no automatic task execution

- [ ] **Step 1: Replace goal-bearing notification construction**

```swift
let msg = ResumeNotificationPresentation.body(
    remainingSteps: pending.unfinishedCount
)
Notifier.notify(title: "Aria", body: msg)
Log.trace("resume: offered pending task")
```

- [ ] **Step 2: Run focused regression tests**

Run: `swift test --filter 'TaskStoreTests|AppWindowModelTests'`

Expected: all selected tests pass; Home resume remains confirmation-gated.

- [ ] **Step 3: Run completion verification**

Run: `make test && make evaluate && make release && codesign --verify --deep --strict .build/Aria.app && git diff --check`

Expected: full suite, evaluation gate, package, signature, and whitespace
checks succeed. Do not commit because this worktree may contain user-owned
changes and no commit was requested.
