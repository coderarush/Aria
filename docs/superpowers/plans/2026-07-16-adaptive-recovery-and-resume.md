# Adaptive Recovery and Confirmed Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Aria use capable Macs at their true safe capacity, recover from current local-model failures, and resume interrupted work through an explicit native confirmation.

**Architecture:** A small injected memory-reading seam feeds the existing runtime policy. `LocalModelHealth` gains a bounded recent observation window that drives policy, while local streaming and warm-up report outcomes into it. The Home card posts a dedicated action notification; the controller confirms its privacy-safe next step and delegates to the existing resume execution path.

**Tech Stack:** Swift 5.9, Swift concurrency/actors, Foundation, AppKit, SwiftUI, XCTest, Make.

## Global Constraints

- Keep all runtime decisions local; never collect prompts, outputs, accounts, or telemetry.
- Keep missing system readings conservative: balanced/cooldown behavior must be safe without a value.
- Keep task resume opt-in, confirmation-gated, and covered by existing action safety/postcondition checks.
- Do not create commits, stage files, or alter the user’s primary worktree.
- Preserve the macOS 26 debug-configuration release workaround and run the release gate.

---

### Task 1: Truthful memory telemetry and recent health policy

**Files:**
- Modify: `Sources/Aria/Services/Models/RuntimeAdaptation.swift`
- Modify: `Sources/Aria/Services/Models/ModelInstaller.swift`
- Modify: `Tests/AriaTests/RuntimeAdaptationTests.swift`
- Modify: `Tests/AriaTests/LocalModelSetupTests.swift`

**Interfaces:**
- Consumes: `RuntimeSignalReader`, `RuntimeCapability`, `LocalModelHealth.Snapshot`.
- Produces: `RuntimeMemoryReader.reclaimableGB(pageSize:free:inactive:purgeable:) -> Int?`, `LocalModelHealth.recentFailureRate(at:)`, and a snapshot whose failure rate represents recent observations.

- [ ] **Step 1: Write failing memory and health-window tests**

```swift
func testReclaimableMemoryCombinesConservativePageClasses() {
    XCTAssertEqual(RuntimeMemoryReader.reclaimableGB(
        pageSize: 16_384, free: 131_072, inactive: 262_144, purgeable: 65_536), 7)
}

func testHealthExpiresOldFailuresBeforeRuntimePolicyUsesThem() async {
    let health = LocalModelHealth(window: 60, maximumObservations: 8)
    let old = Date(timeIntervalSince1970: 0)
    await health.record(ok: false, latency: 0, error: "timeout", at: old)
    await health.record(ok: true, latency: 0.2, at: old.addingTimeInterval(61))
    let snapshot = await health.snapshot(at: old.addingTimeInterval(61))
    XCTAssertEqual(snapshot.recentFailureRate, 0)
}
```

- [ ] **Step 2: Run focused tests to prove the red state**

Run: `swift test --filter RuntimeAdaptationTests --filter LocalModelSetupTests`

Expected: compilation failure because `RuntimeMemoryReader` and the new health-window initializer/snapshot API do not exist.

- [ ] **Step 3: Add conservative memory arithmetic and bounded observations**

```swift
enum RuntimeMemoryReader {
    static func reclaimableGB(pageSize: UInt64, free: UInt64,
                              inactive: UInt64, purgeable: UInt64) -> Int? {
        let pages = free.addingReportingOverflow(inactive)
        guard !pages.overflow else { return nil }
        let total = pages.partialValue.addingReportingOverflow(purgeable)
        guard !total.overflow else { return nil }
        let bytes = total.partialValue.multipliedReportingOverflow(by: pageSize)
        guard !bytes.overflow else { return nil }
        return Int(bytes.partialValue / (1 << 30))
    }
}

actor LocalModelHealth {
    struct Observation: Sendable { let ok: Bool; let at: Date }
    private let window: TimeInterval
    private let maximumObservations: Int
    private var observations: [Observation] = []

    func recentFailureRate(at now: Date = Date()) -> Double? {
        observations.removeAll { now.timeIntervalSince($0.at) > window }
        guard observations.count >= 2 else { return nil }
        return Double(observations.filter { !$0.ok }.count) / Double(observations.count)
    }
}
```

Use `sysctlbyname` page counters and `hw.pagesize` only in the live reader; return `nil` for unavailable/invalid values. Keep lifetime success/failure counts for the existing settings UI, but have `RuntimeAdvisor.refresh()` use `recentFailureRate`.

- [ ] **Step 4: Run focused tests to prove the green state**

Run: `swift test --filter RuntimeAdaptationTests --filter LocalModelSetupTests`

Expected: PASS, including the existing high-memory Performance policy and the new expiry/minimum-sample cases.

### Task 2: Report every local inference path into current health

**Files:**
- Modify: `Sources/Aria/Services/Models/GeminiClient.swift`
- Modify: `Sources/Aria/Application/App/AriaController.swift`
- Modify: `Tests/AriaTests/StreamFallbackTests.swift`
- Modify: `Tests/AriaTests/LocalFirstRouterTests.swift`

**Interfaces:**
- Consumes: `LocalModelHealth.record(ok:latency:error:at:)` and `GeminiClient.streamWithFallback`.
- Produces: `streamWithFallback(..., onPrimaryOutcome:)`, which reports exactly one outcome for a primary stream before fallback; warm-up reports the same local health result.

- [ ] **Step 1: Write failing one-outcome streaming tests**

```swift
func testStreamFallbackReportsPrimaryFailureBeforeCloudFallback() async throws {
    let reported = Locked<[Bool]>([])
    let events = try await collect(GeminiClient.streamWithFallback(
        primary: stream([]), fallback: stream([.text("cloud")]),
        onPrimaryOutcome: { ok, _ in reported.withLock { $0.append(ok) }))
    XCTAssertEqual(events, [.text("cloud")])
    XCTAssertEqual(reported.value, [false])
}
```

- [ ] **Step 2: Run focused test to prove the red state**

Run: `swift test --filter StreamFallbackTests`

Expected: compilation failure because `onPrimaryOutcome` does not exist.

- [ ] **Step 3: Implement single-outcome observation and wire local chat**

```swift
static func streamWithFallback(
    primary: AsyncThrowingStream<StreamEvent, Error>,
    fallback: @escaping @Sendable () -> AsyncThrowingStream<StreamEvent, Error>,
    firstTokenTimeout: TimeInterval = 12,
    onPrimaryOutcome: @escaping @Sendable (Bool, TimeInterval) -> Void = { _, _ in }
) -> AsyncThrowingStream<StreamEvent, Error>
```

Start a clock when the primary is created. The lock-backed state must report
`true` once when the first primary event wins, or `false` once when an empty,
errored, or timed-out primary triggers fallback. Never report a second outcome
after a stream has produced user-visible text. Pass a closure only from the
local-chat invocation that calls `LocalModelHealth.shared.record`; fast-cloud
and Gemini calls keep the default no-op.

In `warmLocalModel()`, replace each ignored `try?` with `do/catch`, measure
duration, record success/failure, and always release the limiter using `defer`.

- [ ] **Step 4: Run focused tests to prove the green state**

Run: `swift test --filter StreamFallbackTests --filter LocalFirstRouterTests`

Expected: PASS; fallback output and existing cancellation behavior remain unchanged.

### Task 3: Confirmed native Home resume and live card refresh

**Files:**
- Modify: `Sources/Aria/UI/Desktop/AppWindowController.swift`
- Modify: `Sources/Aria/UI/Desktop/AppWindowPanes.swift`
- Modify: `Sources/Aria/UI/Desktop/AppWindowView.swift`
- Modify: `Sources/Aria/Execution/Scheduler/TaskStore.swift`
- Modify: `Sources/Aria/Application/App/AriaController.swift`
- Modify: `Tests/AriaTests/AppWindowModelTests.swift`
- Modify: `Tests/AriaTests/TaskStoreTests.swift`

**Interfaces:**
- Consumes: `TaskProgressSummary.state`, `TaskStore.pending()`, `AgentOrchestrator.resumeTask(emit:)`.
- Produces: `.ariaResumeTask`, `.ariaTaskStoreDidChange`, `TaskProgressSummary.canResume`, and a Home-card action that only posts resume for `.resumable` work.

- [ ] **Step 1: Write failing pure UI/task-state tests**

```swift
func testResumableTaskOffersResumeButRunningTaskDoesNot() {
    XCTAssertTrue(TaskProgressSummary(state: .resumable, goal: "g", value: "Ready to resume",
                                      progress: "0 of 1 step complete", nextStep: "Read", detail: "d").canResume)
    XCTAssertFalse(TaskProgressSummary(state: .running, goal: "g", value: "Working now",
                                       progress: "0 of 1 step complete", nextStep: "Read", detail: "d").canResume)
}

func testSaveAndClearPublishTaskStoreChange() async {
    let expectation = expectation(forNotification: .ariaTaskStoreDidChange, object: nil)
    await store.save(task)
    await fulfillment(of: [expectation], timeout: 1)
}
```

- [ ] **Step 2: Run focused tests to prove the red state**

Run: `swift test --filter AppWindowModelTests --filter TaskStoreTests`

Expected: compilation failure because `canResume` and `.ariaTaskStoreDidChange` do not exist.

- [ ] **Step 3: Add the native control and controller confirmation**

```swift
extension Notification.Name {
    static let ariaResumeTask = Notification.Name("aria.resumeTask")
    static let ariaTaskStoreDidChange = Notification.Name("aria.taskStoreDidChange")
}

// Home card, only when task.canResume:
Button("Resume task") {
    NotificationCenter.default.post(name: .ariaResumeTask, object: nil)
}
.buttonStyle(.borderedProminent)
.controlSize(.small)
```

`TaskStore.save` and `TaskStore.clear` post `.ariaTaskStoreDidChange` after the
filesystem operation. `AppWindowView` listens for that event and runs the
existing `model.refresh()` task, keeping the read-only card current.

`AriaController` retains a notification observer for `.ariaResumeTask`. Its
handler rejects duplicate/busy requests, fetches the pending task, and uses a
dedicated `NSAlert` whose Cancel button is first/default and whose text contains
only `goal`, the next step summary, and remaining step count. On approval it
calls `runAutonomousTask(pending.goal, resume: true)`; on cancellation or a
missing task it leaves persistence untouched.

- [ ] **Step 4: Run focused tests to prove the green state**

Run: `swift test --filter AppWindowModelTests --filter TaskStoreTests`

Expected: PASS; a Home card can offer only explicit resumable work, and store
changes notify observers without retaining task input/output in UI state.

### Task 4: Make the Mirror setting honest until transport exists

**Files:**
- Modify: `Sources/Aria/UI/Settings/SettingsView.swift`
- Modify: `Tests/AriaTests/SettingsTests.swift`

**Interfaces:**
- Consumes: `MirrorSettings` and the still-unimplemented `MirrorBridge`.
- Produces: an explicitly unavailable companion setting rather than an enabled-looking green status.

- [ ] **Step 1: Write the failing settings-copy test**

```swift
func testMirrorBridgeRemainsUnavailableUntilTransportExists() {
    XCTAssertEqual(MirrorBridge.availability, .unavailable)
}
```

- [ ] **Step 2: Run focused test to prove the red state**

Run: `swift test --filter SettingsTests`

Expected: compilation failure because `MirrorBridge.availability` does not exist.

- [ ] **Step 3: Add truthful availability and disable the toggle**

```swift
enum MirrorAvailability { case unavailable }
static let availability: MirrorAvailability = .unavailable
```

Render the Mirror setting with a neutral unavailable badge and a disabled
toggle. Keep the saved settings values intact for forward compatibility, but do
not imply that enabling one opens a listener or accepts network commands.

- [ ] **Step 4: Run focused test to prove the green state**

Run: `swift test --filter SettingsTests`

Expected: PASS; the setting states that the companion is not available rather
than presenting an enabled-but-nonfunctional connection.

### Task 5: Full integration verification

**Files:**
- Modify: `docs/superpowers/specs/2026-07-16-adaptive-recovery-and-resume-design.md` only if implementation changes an accepted interface.

- [ ] **Step 1: Run the complete unit suite**

Run: `make test`

Expected: all tests pass; capture the exact total and skipped count.

- [ ] **Step 2: Run the deterministic release evaluation**

Run: `make evaluate`

Expected: `EvaluationGateTests` passes, including the end-to-end local scenario suite.

- [ ] **Step 3: Build the release through its real prerequisite path**

Run: `make release`

Expected: evaluation target, release guard, bundle assembly, and signing succeed.

- [ ] **Step 4: Verify the shipped artifact and patch hygiene**

Run: `codesign --verify --deep --strict .build/Aria.app`

Expected: exit status 0.

Run: `git diff --check`

Expected: exit status 0.
