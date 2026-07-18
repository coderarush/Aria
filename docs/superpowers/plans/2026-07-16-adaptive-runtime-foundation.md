# Adaptive Runtime Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adapt Aria’s local-model behavior to each Mac’s active capacity, power, and thermal conditions, then show that truthful state in the native Home pane.

**Architecture:** A pure RuntimePolicy derives an explainable RuntimeRecommendation from a fixture-friendly RuntimeCapability. RuntimeAdvisor supplies the live snapshot to LocalFirstRouter and AppWindowModel. The policy can only cap or defer local work; it never raises a model tier, changes user settings, or starts local work while constrained.

**Tech Stack:** Swift 6, Swift Concurrency, SwiftUI/AppKit, Foundation/ProcessInfo, XCTest, existing Ollama ModelProvider.

## Global Constraints

- Minimum platform remains macOS 14 and no third-party dependency is added.
- Preserve the orb, voice, local-first defaults, cloud fallback, approvals, receipts, and undo.
- Dynamic hardware/power reads are injected; policy tests must never depend on the host machine.
- Runtime adaptation may only reduce local work or choose cloud fallback. It never enables a disabled setting or overrides privacy choices.
- Run a focused failing XCTest before every production behavior change, then rerun it after the minimal implementation.
- Do not commit or push unless the user explicitly asks.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/Aria/Services/Models/RuntimeAdaptation.swift` | Capability/state types, pure policy, injectable signal reader, and cached advisor. |
| `Sources/Aria/Services/Models/LocalFirstRouter.swift` | Enforces runtime allowance before Ollama probes and resolves a capped model. |
| `Sources/Aria/Application/App/AriaController.swift` | Skips model warming when the runtime declines local work. |
| `Sources/Aria/UI/Desktop/AppWindowModel.swift` | Creates pure status rows from the runtime snapshot. |
| `Sources/Aria/UI/Desktop/AppWindowPanes.swift` | Displays the status rows with existing native card primitives. |
| `Tests/AriaTests/RuntimeAdaptationTests.swift` | Full posture policy and injected-advisor coverage. |
| `Tests/AriaTests/LocalFirstRouterTests.swift` | No-probe constraint and normal local-route regression coverage. |
| `Tests/AriaTests/AppWindowModelTests.swift` | Plain-language status row coverage. |

---

### Task 1: Capability types and deterministic posture policy

**Files:**

- Create: `Sources/Aria/Services/Models/RuntimeAdaptation.swift`
- Create: `Tests/AriaTests/RuntimeAdaptationTests.swift`

**Produces:**

~~~swift
enum RuntimePowerSource: String, Codable, Sendable { case ac, battery, unavailable }
enum RuntimeThermalState: String, Codable, Sendable { case nominal, fair, serious, critical }
enum RuntimePosture: String, Codable, Sendable { case performance, balanced, batterySaver, cooldown, constrained }

struct RuntimeCapability: Codable, Equatable, Sendable {
    let chip: String
    let ramGB: Int
    let freeDiskGB: Int
    let powerSource: RuntimePowerSource
    let batteryPercent: Int?
    let lowPowerMode: Bool
    let thermalState: RuntimeThermalState
    let availableMemoryGB: Int?
    let lastLocalLatency: TimeInterval?
    let localFailureRate: Double?
}

struct RuntimeRecommendation: Codable, Equatable, Sendable {
    let posture: RuntimePosture
    let permitsLocalPlanning: Bool
    let permitsLocalChat: Bool
    let maxConcurrentLocalRequests: Int
    let planningModelCap: String?
    let chatModelCap: String?
    let reason: String
}

enum RuntimePolicy {
    static func select(_ capability: RuntimeCapability) -> RuntimeRecommendation
    static func effectiveModel(selected: String, cap: String?) -> String
}
~~~

- [ ] **Step 1: Write failing policy tests**

Create `Tests/AriaTests/RuntimeAdaptationTests.swift`:

~~~swift
import XCTest
@testable import Aria

final class RuntimeAdaptationTests: XCTestCase {
    private func makeCapability(power: RuntimePowerSource = .ac, battery: Int? = 92,
                                lowPower: Bool = false, thermal: RuntimeThermalState = .nominal,
                                ram: Int = 16, disk: Int = 40, memory: Int? = 8,
                                latency: TimeInterval? = 1.2, failures: Double? = 0) -> RuntimeCapability {
        RuntimeCapability(chip: "Apple M4", ramGB: ram, freeDiskGB: disk,
                          powerSource: power, batteryPercent: battery,
                          lowPowerMode: lowPower, thermalState: thermal,
                          availableMemoryGB: memory, lastLocalLatency: latency,
                          localFailureRate: failures)
    }

    func testHealthyACOn16GBUsesBalancedLocalWork() {
        let result = RuntimePolicy.select(makeCapability())
        XCTAssertEqual(result.posture, .balanced)
        XCTAssertTrue(result.permitsLocalPlanning)
        XCTAssertTrue(result.permitsLocalChat)
        XCTAssertEqual(result.maxConcurrentLocalRequests, 1)
        XCTAssertEqual(result.planningModelCap, "qwen3:8b")
    }

    func testHealthyACOn24GBUsesPerformancePosture() {
        let result = RuntimePolicy.select(makeCapability(ram: 24, disk: 48, memory: 14))
        XCTAssertEqual(result.posture, .performance)
        XCTAssertEqual(result.maxConcurrentLocalRequests, 2)
        XCTAssertEqual(result.planningModelCap, "qwen3:14b")
    }

    func testBatteryUsesSmallModelsAndOneRequest() {
        let result = RuntimePolicy.select(makeCapability(power: .battery, battery: 73))
        XCTAssertEqual(result.posture, .batterySaver)
        XCTAssertEqual(result.planningModelCap, "qwen3:4b")
        XCTAssertEqual(result.chatModelCap, "llama3.2:1b")
        XCTAssertEqual(result.maxConcurrentLocalRequests, 1)
    }

    func testLowPowerAndLowBatteryCooldownsPlanning() {
        let result = RuntimePolicy.select(makeCapability(power: .battery, battery: 18, lowPower: true))
        XCTAssertEqual(result.posture, .cooldown)
        XCTAssertFalse(result.permitsLocalPlanning)
        XCTAssertTrue(result.permitsLocalChat)
        XCTAssertTrue(result.reason.localizedCaseInsensitiveContains("Low Power"))
    }

    func testCriticalThermalsDisableAllLocalRouting() {
        let result = RuntimePolicy.select(makeCapability(thermal: .critical))
        XCTAssertEqual(result.posture, .constrained)
        XCTAssertFalse(result.permitsLocalPlanning)
        XCTAssertFalse(result.permitsLocalChat)
        XCTAssertEqual(result.maxConcurrentLocalRequests, 0)
    }

    func testLowDiskLowMemoryAndPoorHealthConstrainOrCooldown() {
        XCTAssertEqual(RuntimePolicy.select(makeCapability(disk: 4)).posture, .constrained)
        XCTAssertEqual(RuntimePolicy.select(makeCapability(memory: 1)).posture, .constrained)
        XCTAssertEqual(RuntimePolicy.select(makeCapability(latency: 16)).posture, .cooldown)
        XCTAssertEqual(RuntimePolicy.select(makeCapability(failures: 0.51)).posture, .cooldown)
    }

    func testEffectiveModelCanOnlyStepDownKnownModels() {
        XCTAssertEqual(RuntimePolicy.effectiveModel(selected: "qwen3:14b", cap: "qwen3:4b"), "qwen3:4b")
        XCTAssertEqual(RuntimePolicy.effectiveModel(selected: "qwen3:4b", cap: "qwen3:14b"), "qwen3:4b")
        XCTAssertEqual(RuntimePolicy.effectiveModel(selected: "custom-model", cap: "qwen3:4b"), "custom-model")
    }
}
~~~

- [ ] **Step 2: Run the test and confirm it fails because the types do not exist**

Run: `swift test --filter RuntimeAdaptationTests`

Expected: compilation fails for `RuntimeCapability`, `RuntimeRecommendation`, and `RuntimePolicy`.

- [ ] **Step 3: Implement the pure policy**

Create `RuntimeAdaptation.swift`. Implement the declared models and this precise precedence:

1. critical thermal state, free disk less than 5 GB, or available memory at/below 1 GB → `.constrained`, no local work, zero concurrency;
2. serious thermal state → `.cooldown`, planning false, chat true, one concurrency, 4B/1B caps;
3. Low Power Mode on battery at/below 25% → the same `.cooldown`;
4. local failure rate above 0.5 or last latency over 15 seconds → the same `.cooldown`;
5. battery otherwise → `.batterySaver`, planning/chat true, one concurrency, 4B/1B caps;
6. AC with at least 24 GB RAM, 16 GB disk, and 6 GB available memory → `.performance`, two concurrency, 14B/3B caps;
7. otherwise → `.balanced`, one concurrency and 4B/1B caps below 16 GB RAM or 8B/3B caps at 16 GB+.

Use these exact return forms for the first and final branches:

~~~swift
if c.thermalState == .critical || c.freeDiskGB < 5 || (c.availableMemoryGB ?? 2) <= 1 {
    return RuntimeRecommendation(posture: .constrained, permitsLocalPlanning: false,
        permitsLocalChat: false, maxConcurrentLocalRequests: 0,
        planningModelCap: nil, chatModelCap: nil,
        reason: c.thermalState == .critical ? "Mac is too warm for local work" : "Mac capacity is constrained")
}
return RuntimeRecommendation(posture: .balanced, permitsLocalPlanning: true,
    permitsLocalChat: true, maxConcurrentLocalRequests: 1,
    planningModelCap: c.ramGB < 16 ? "qwen3:4b" : "qwen3:8b",
    chatModelCap: c.ramGB < 16 ? "llama3.2:1b" : "llama3.2:3b",
    reason: "Balanced for this Mac")
~~~

`effectiveModel` ranks only `qwen3:4b`, `qwen3:8b`, and `qwen3:14b`; unknown tags return unchanged. It returns the cap only when both known ranks exist and the selected model is larger.

- [ ] **Step 4: Verify the focused policy tests pass**

Run: `swift test --filter RuntimeAdaptationTests`

Expected: all seven tests pass without reading live hardware.

---

### Task 2: Live advisor and no-probe router guard

**Files:**

- Modify: `Sources/Aria/Services/Models/RuntimeAdaptation.swift`
- Modify: `Sources/Aria/Services/Models/LocalFirstRouter.swift`
- Modify: `Sources/Aria/Application/App/AriaController.swift:123-149`
- Modify: `Tests/AriaTests/RuntimeAdaptationTests.swift`
- Modify: `Tests/AriaTests/LocalFirstRouterTests.swift`

**Produces:**

~~~swift
struct RuntimeSignalReader: Sendable {
    let readPowerSource: @Sendable () -> RuntimePowerSource
    let readBatteryPercent: @Sendable () -> Int?
    let readLowPowerMode: @Sendable () -> Bool
    let readThermalState: @Sendable () -> RuntimeThermalState
    let readAvailableMemoryGB: @Sendable () -> Int?
}

actor RuntimeAdvisor {
    static let shared: RuntimeAdvisor
    init(hardware: @escaping @Sendable () -> HardwareProfiler.Profile = HardwareProfiler.profile,
         signals: RuntimeSignalReader = .live,
         health: LocalModelHealth = .shared)
    func refresh() async -> RuntimeRecommendation
    func recommendation() async -> RuntimeRecommendation
    func capability() async -> RuntimeCapability
}
~~~

- [ ] **Step 1: Write failing injected-advisor and no-probe tests**

Append this test to `RuntimeAdaptationTests.swift`:

~~~swift
func testAdvisorUsesInjectedSignalsAndHealth() async {
    let signals = RuntimeSignalReader(readPowerSource: { .battery }, readBatteryPercent: { 19 },
        readLowPowerMode: { true }, readThermalState: { .nominal }, readAvailableMemoryGB: { 6 })
    let health = LocalModelHealth()
    await health.record(ok: false, latency: 0, error: "timeout")
    await health.record(ok: false, latency: 0, error: "timeout")
    let advisor = RuntimeAdvisor(
        hardware: { .init(chip: "Test Mac", ramGB: 16, freeDiskGB: 40, recommendedModel: "qwen3:8b") },
        signals: signals, health: health)
    let result = await advisor.refresh()
    XCTAssertEqual(result.posture, .cooldown)
    XCTAssertEqual((await advisor.capability()).batteryPercent, 19)
}
~~~

Append this test to `LocalFirstRouterTests.swift`:

~~~swift
func testConstrainedRuntimeGoesCloudWithoutProbingProvider() async {
    let d = defaults()
    d.set(true, forKey: "app.localFirst")
    var probed = false
    let constrained = RuntimeRecommendation(posture: .constrained, permitsLocalPlanning: false,
        permitsLocalChat: false, maxConcurrentLocalRequests: 0, planningModelCap: nil,
        chatModelCap: nil, reason: "Mac is too warm for local work")
    let router = LocalFirstRouter(defaults: d,
        makeProvider: { _ in DeterministicProvider(script: [:], fallback: "unused") },
        availability: { probed = true; return true },
        runtimeRecommendation: { constrained })
    let decision = await router.decide(taskClass: .planning)
    XCTAssertEqual(decision.tier, .cloud)
    XCTAssertTrue(decision.reason.contains("too warm"))
    XCTAssertFalse(probed)
}
~~~

- [ ] **Step 2: Run focused tests and confirm the missing API failure**

Run: `swift test --filter 'RuntimeAdaptationTests|LocalFirstRouterTests'`

Expected: compilation fails because `RuntimeSignalReader`, `RuntimeAdvisor`, and the router’s `runtimeRecommendation` initializer argument are absent.

- [ ] **Step 3: Implement advisor sampling and route enforcement**

Add `RuntimeSignalReader.live` using `ProcessInfo.processInfo.isLowPowerModeEnabled` and `ProcessInfo.processInfo.thermalState`. Map every thermal state exactly. Read IOKit power/battery information when the platform supplies it; if it does not, return `.unavailable` and `nil`. Return nil—not an estimate—for unavailable memory pressure.

`RuntimeAdvisor.refresh()` must read `HardwareProfiler.profile()`, read every injected signal, retrieve `LocalModelHealth.Snapshot`, calculate failure rate as `Double(failures) / Double(successes + failures)` only when the denominator is nonzero, cache the new capability/recommendation, and return it. `recommendation()` lazily calls `refresh()` until a cache exists. It persists no data.

Extend `LocalFirstRouter.init` with:

~~~swift
runtimeRecommendation: @escaping @Sendable () async -> RuntimeRecommendation = {
    await RuntimeAdvisor.shared.recommendation()
}
~~~

Store it as a private closure. In `decide(taskClass:)`, after existing toggle/class guards and before availability probing:

~~~swift
let runtime = await runtimeRecommendation()
guard runtime.permitsLocalPlanning else {
    return RoutingDecision(taskClass: taskClass, tier: .cloud, reason: runtime.reason)
}
~~~

In `tryLocal(prompt:temperature:)`, return nil before provider creation when planning is not permitted. Otherwise make the provider with:

~~~swift
let effective = RuntimePolicy.effectiveModel(selected: localModelName, cap: runtime.planningModelCap)
let p = makeProvider(effective)
~~~

In `chatGoesLocal()`, check `permitsLocalChat` before inspecting the 30-second probe cache. Add an `effectivePlanningModelName` computed property so `AriaController.warmLocalModel()` can choose the capped planning model. Refresh through that property, return without any Ollama call when local planning is forbidden, and re-check it in the four-minute warming loop.

- [ ] **Step 4: Verify focused behavior and old fallback behavior**

Run: `swift test --filter 'RuntimeAdaptationTests|LocalFirstRouterTests'`

Expected: all new tests pass, all pre-existing local-routing tests pass, and the constrained test demonstrates that its availability closure is never called.

---

### Task 3: Native Home status card

**Files:**

- Modify: `Sources/Aria/UI/Desktop/AppWindowModel.swift:237-295`
- Modify: `Sources/Aria/UI/Desktop/AppWindowPanes.swift:9-100`
- Modify: `Tests/AriaTests/AppWindowModelTests.swift`

**Produces:**

~~~swift
enum RuntimeStatusTone: Equatable { case positive, neutral, attention }

struct RuntimeStatusRow: Equatable, Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tone: RuntimeStatusTone
}
~~~

- [ ] **Step 1: Write failing formatter tests**

Add to `AppWindowModelTests.swift`:

~~~swift
func testRuntimeRowsNameBatterySaverInPlainLanguage() {
    let capability = RuntimeCapability(chip: "Apple M4", ramGB: 16, freeDiskGB: 40,
        powerSource: .battery, batteryPercent: 58, lowPowerMode: false,
        thermalState: .nominal, availableMemoryGB: 6, lastLocalLatency: 1.2, localFailureRate: 0)
    let recommendation = RuntimeRecommendation(posture: .batterySaver,
        permitsLocalPlanning: true, permitsLocalChat: true, maxConcurrentLocalRequests: 1,
        planningModelCap: "qwen3:4b", chatModelCap: "llama3.2:1b",
        reason: "Preserving battery while keeping Aria local")
    let health = LocalModelHealth.Snapshot(successes: 4, failures: 0,
        lastLatency: 1.2, lastError: nil, lastSuccessAt: Date())
    let rows = AppWindowModel.runtimeStatusRows(capability: capability,
                                                recommendation: recommendation, health: health)
    XCTAssertEqual(rows.first?.title, "Runtime")
    XCTAssertEqual(rows.first?.value, "Battery saver")
    XCTAssertTrue(rows.first?.detail.contains("58%") ?? false)
    XCTAssertEqual(rows.first?.tone, .neutral)
}

func testRuntimeRowsFlagConstrainedState() {
    let capability = RuntimeCapability(chip: "Apple M4", ramGB: 16, freeDiskGB: 40,
        powerSource: .ac, batteryPercent: nil, lowPowerMode: false,
        thermalState: .critical, availableMemoryGB: 6, lastLocalLatency: nil, localFailureRate: 1)
    let recommendation = RuntimeRecommendation(posture: .constrained,
        permitsLocalPlanning: false, permitsLocalChat: false, maxConcurrentLocalRequests: 0,
        planningModelCap: nil, chatModelCap: nil, reason: "Mac is too warm for local work")
    let health = LocalModelHealth.Snapshot(successes: 0, failures: 2,
        lastLatency: nil, lastError: "timeout", lastSuccessAt: nil)
    let rows = AppWindowModel.runtimeStatusRows(capability: capability,
                                                recommendation: recommendation, health: health)
    XCTAssertEqual(rows.first?.value, "Local work paused")
    XCTAssertEqual(rows.first?.tone, .attention)
}
~~~

- [ ] **Step 2: Run and confirm the expected missing formatter failure**

Run: `swift test --filter AppWindowModelTests`

Expected: compilation fails because the status row types and `runtimeStatusRows` do not exist.

- [ ] **Step 3: Implement the read-only snapshot and restrained card**

Add `@Published private(set) var runtimeStatus: [RuntimeStatusRow] = []` to `AppWindowModel`. In `refresh()`, load the existing store reads concurrently with:

~~~swift
async let runtimeCapability = RuntimeAdvisor.shared.capability()
async let runtimeRecommendation = RuntimeAdvisor.shared.recommendation()
async let localHealth = LocalModelHealth.shared.snapshot()
runtimeStatus = Self.runtimeStatusRows(capability: await runtimeCapability,
    recommendation: await runtimeRecommendation, health: await localHealth)
~~~

Implement `runtimeStatusRows` as exactly three rows:

- Runtime: values `Performance`, `Balanced`, `Battery saver`, `Cooling down`, or `Local work paused`; constrained is attention, cooldown and battery saver are neutral, other states positive. Include battery percentage only when it exists.
- Local model: `Ready · 1.2s last reply` for known latency, `Needs attention` when failures exceed successes, or `Not measured yet`. Never show raw provider errors.
- This Mac: chip, RAM, and free disk in a short sentence.

Insert `runtimeStatus` after `hero` in `HomePane`. It uses `AriaCard`, a `Label("Aria status", systemImage: "waveform.path.ecg")`, and one private `RuntimeStatusCell` per row. Each cell uses only SF Symbols, existing system fonts, semantic foreground colors, and an accessibility-combined label. Use `ViewThatFits` to choose a horizontal HStack at normal width or a vertical VStack in a narrow 900×600 window. Do not add animation, gradients, non-native controls, or a separate design system.

- [ ] **Step 4: Verify the model/UI seam compiles and focused tests pass**

Run:

~~~bash
swift test --filter 'AppWindowModelTests|RuntimeAdaptationTests|LocalFirstRouterTests'
swift build
~~~

Expected: every focused test passes and the app target compiles.

---

### Task 4: Full regression and release evidence

**Files:**

- Modify: `docs/superpowers/specs/2026-07-16-adaptive-operator-design.md` only if an implemented public contract differs from the locked design.

- [ ] **Step 1: Audit the implementation against acceptance cases**

Verify this table against tests and code:

| Condition | Required result |
|---|---|
| AC, 16 GB | balanced and local work allowed |
| AC, 24 GB | performance and 14B cap |
| Battery | battery saver with smaller caps |
| Low Power plus <=25% battery | cooldown and planning blocked |
| Critical thermal / low disk / low memory | constrained and no availability probe |
| Home | plain language for runtime, local model, and Mac status |

- [ ] **Step 2: Run the complete test suite**

Run: `make test`

Expected: exit 0; record the final XCTest executed/failure summary.

- [ ] **Step 3: Verify release safeguards and app bundle**

Run:

~~~bash
make verify-release
make release
codesign --verify --deep --strict .build/Aria.app
~~~

Expected: the release mitigation guard passes, the app bundle is produced, and codesign exits 0.

- [ ] **Step 4: Review only planned changes and preserve pre-existing work**

Run:

~~~bash
git diff --check
git status --short
git diff -- Sources/Aria/Services/Models/RuntimeAdaptation.swift Sources/Aria/Services/Models/LocalFirstRouter.swift Sources/Aria/Application/App/AriaController.swift Sources/Aria/UI/Desktop/AppWindowModel.swift Sources/Aria/UI/Desktop/AppWindowPanes.swift Tests/AriaTests/RuntimeAdaptationTests.swift Tests/AriaTests/LocalFirstRouterTests.swift Tests/AriaTests/AppWindowModelTests.swift
~~~

Expected: no whitespace errors. Do not stage, commit, discard, or overwrite the pre-existing workflow and video changes.
