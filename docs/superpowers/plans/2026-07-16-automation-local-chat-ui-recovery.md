# Automation, Local Chat, and UI Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop unwanted background notes, isolate automation tests from live data, route conversation through the installed local model, and make Aria's command and navigation surfaces clearer.

**Architecture:** Inject persistence dependencies into automation tools, sanitize duplicate persisted definitions at the store boundary, and gate the coordinator with an explicit user setting. Keep model selection and UI sizing in pure presentation/policy types that XCTest can verify before AppKit or SwiftUI renders them.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Foundation, Ollama, XCTest.

## Global Constraints

- Do not delete existing Apple Notes automatically.
- Background agents default to globally paused until the user opts in.
- Preserve unique agent definitions and all run history.
- Test code must use temporary files and must never touch `AgentStore.shared`.
- Preserve eager SwiftUI containers; do not introduce `List`, `Form`, or `NavigationSplitView`.
- Do not stage or commit because the user did not request version-control mutations.
- Keep Aria stopped until the fixed, signed build is ready and live agent metadata has been quarantined.

---

### Task 1: Isolate automation tools from live persistence

**Files:**
- Modify: `Sources/Aria/Execution/Actions/AutomationTool.swift`
- Modify: `Tests/AriaTests/AutomationToolTests.swift`

**Interfaces:**
- Produces: `AutomationCreateTool.init(store: AgentStore = .shared)`
- Produces: `AutomationListTool.init(store: AgentStore = .shared)`
- Preserves: default construction in `ToolRegistry`

- [x] **Step 1: Rewrite the first create/list tests to require injected stores**

Create one temporary `AgentStore` per test and pass the same store into the tool under test:

```swift
private func store() -> AgentStore {
    AgentStore(fileURL: tempStoreURL())
}

func testCreateCalendarAutomationUsesInjectedStore() async throws {
    let store = store()
    let tool = AutomationCreateTool(store: store)
    let result = try await tool.run(input: [
        "name": "Standup prep",
        "trigger_type": "calendar",
        "trigger_value": "Standup",
        "goal": "Prepare standup notes"
    ])

    XCTAssertTrue(result.success)
    let stored = await store.all().first { $0.name == "Standup prep" }
    XCTAssertNotNil(stored)
}

func testListReadsOnlyItsInjectedStore() async throws {
    let store = store()
    _ = try await AutomationCreateTool(store: store).run(input: [
        "name": "List test agent",
        "trigger_type": "email",
        "trigger_value": "from:alice",
        "goal": "Reply to Alice"
    ])

    let result = try await AutomationListTool(store: store).run(input: [:])
    XCTAssertTrue(result.output.contains("List test agent"))
}
```

Update every remaining `AutomationToolTests` creation/list assertion to use its own temporary store. Remove the comment that accepts shared-store writes.

- [x] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter AutomationToolTests`

Expected: compilation fails because neither tool accepts `store:`.

- [x] **Step 3: Inject the store into both production tools**

```swift
struct AutomationCreateTool: AriaTool {
    private let store: AgentStore

    init(store: AgentStore = .shared) {
        self.store = store
    }

    // existing metadata and parsing remain unchanged
    // replace AgentStore.shared.upsert(agent) with store.upsert(agent)
}

struct AutomationListTool: AriaTool {
    private let store: AgentStore

    init(store: AgentStore = .shared) {
        self.store = store
    }

    // replace AgentStore.shared.all() with store.all()
}
```

- [x] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter AutomationToolTests`

Expected: all automation-tool tests pass without changing the live agent count.

### Task 2: Quarantine duplicate agents and add a global pause

**Files:**
- Modify: `Sources/Aria/Execution/Workers/BackgroundAgent.swift`
- Modify: `Sources/Aria/Execution/Workers/AgentCoordinator.swift`
- Modify: `Sources/Aria/Application/Configuration/AppSettings.swift`
- Modify: `Sources/Aria/Application/App/AriaController.swift`
- Modify: `Sources/Aria/UI/Settings/SettingsView.swift`
- Modify: `Tests/AriaTests/BackgroundAgentTests.swift`
- Modify: `Tests/AriaTests/AgentCoordinatorTests.swift`
- Modify: `Tests/AriaTests/SettingsTests.swift`

**Interfaces:**
- Produces: `AgentStore.quarantiningDuplicateDefinitions(_:)`
- Produces: `AppSettings.backgroundAgentsEnabled`, persisted as `app.backgroundAgentsEnabled`
- Produces: `AgentCoordinator.init(store:isEnabled:isBusy:runner:notify:)`
- Consumes: `.ariaAgentsChanged` to rebuild or stop folder watchers

- [x] **Step 1: Add failing duplicate-quarantine tests**

```swift
func testDuplicateDefinitionsCollapseToOnePausedAgent() async {
    let url = tempURL()
    let store = AgentStore(fileURL: url)
    let first = BackgroundAgent(name: "Standup prep", goal: "Prepare notes",
                                trigger: .daily(hour: 9, minute: 0))
    let second = BackgroundAgent(name: "Standup prep", goal: "Prepare notes",
                                 trigger: .daily(hour: 9, minute: 0))

    let sanitized = AgentStore.quarantiningDuplicateDefinitions([first, second])

    XCTAssertEqual(sanitized.count, 1)
    XCTAssertFalse(sanitized[0].enabled)
    XCTAssertTrue(sanitized[0].lastOutcome?.contains("duplicate") == true)
}
```

Also assert that a unique agent remains byte-for-byte equal and enabled.

- [x] **Step 2: Add failing global-pause tests**

In `SettingsTests`, assert a fresh `AppSettings` has `backgroundAgentsEnabled == false`. In `AgentCoordinatorTests`, inject `isEnabled: { false }`, sweep a due agent, and assert the runner and run history remain untouched.

- [x] **Step 3: Run the focused tests and verify RED**

Run: `swift test --filter 'BackgroundAgentTests|AgentCoordinatorTests|SettingsTests'`

Expected: compilation fails because the quarantine API, setting, and `isEnabled` coordinator dependency do not exist.

- [x] **Step 4: Implement load-boundary quarantine**

Add a pure sanitizer that groups by normalized name, normalized goal, and equal trigger. For any group with multiple definitions, retain the most recently run representative, set `enabled = false`, and set:

```swift
representative.lastOutcome = "Paused because duplicate automation definitions were found."
```

In `AgentStore.init`, sanitize the loaded state before assigning it. If agents changed, persist the sanitized state immediately with a static encoder helper. Do not modify `state.runs`.

- [x] **Step 5: Implement the global setting and coordinator gate**

Add to `AppSettings`:

```swift
@Published var backgroundAgentsEnabled: Bool {
    didSet { defaults.set(backgroundAgentsEnabled, forKey: K.backgroundAgentsEnabled) }
}
```

Load it with a default of false and define `K.backgroundAgentsEnabled = "app.backgroundAgentsEnabled"`.

Add `isEnabled: () -> Bool = { true }` to `AgentCoordinator`. Guard `sweep` and `refreshWatchers`; when disabled, `refreshWatchers` must stop and clear existing watchers before returning. Inject `{ AppSettings.shared.backgroundAgentsEnabled }` from `AriaController`.

- [x] **Step 6: Add the visible master switch**

At the top of `AgentsSettingsTab`, render:

```swift
@ObservedObject private var settings = AppSettings.shared

SSection("Background execution") {
    Toggle("Allow background agents to run", isOn: $settings.backgroundAgentsEnabled)
    Text(settings.backgroundAgentsEnabled
         ? "Scheduled and watched automations may run when Aria is idle."
         : "Paused. No scheduled or watched automation will run.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

Observe the setting and post `.ariaAgentsChanged` so watcher state updates immediately.

- [x] **Step 7: Run focused tests and verify GREEN**

Run: `swift test --filter 'BackgroundAgentTests|AgentCoordinatorTests|SettingsTests'`

Expected: duplicate quarantine, default pause, existing schedule behavior, and settings persistence all pass.

### Task 3: Route live chat through the configured installed model

**Files:**
- Modify: `Sources/Aria/Services/Models/LocalFirstRouter.swift`
- Modify: `Tests/AriaTests/LocalFirstRouterTests.swift`

**Interfaces:**
- Produces: `LocalFirstRouter.localChatModelName` falling back to `localModelName`
- Preserves: explicit `app.localChatModel` and runtime family-aware caps

- [x] **Step 1: Add the failing model-selection test**

```swift
func testChatUsesConfiguredLocalModelWhenNoSeparateChatModelExists() async {
    let d = defaults()
    d.set("qwen3:8b", forKey: "app.localModelName")
    let router = LocalFirstRouter(
        defaults: d,
        makeProvider: { _ in DeterministicProvider(script: [:], fallback: "local") },
        runtimeRecommendation: { Self.healthyRuntime })

    XCTAssertEqual(await router.effectiveChatModelName(), "qwen3:8b")
}
```

- [x] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter LocalFirstRouterTests/testChatUsesConfiguredLocalModelWhenNoSeparateChatModelExists`

Expected: failure because the router returns `llama3.2:3b`.

- [x] **Step 3: Implement selected-model fallback**

```swift
var localChatModelName: String {
    let explicit = defaults.string(forKey: Self.chatModelKey)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !explicit.isEmpty { return explicit }
    let selected = localModelName.trimmingCharacters(in: .whitespacesAndNewlines)
    return selected.isEmpty ? OllamaProvider.defaultModel : selected
}
```

- [x] **Step 4: Verify router tests and live Ollama output**

Run: `swift test --filter LocalFirstRouterTests`

Expected: all router tests pass.

Run a non-streaming `/api/chat` request against `qwen3:8b` with `think:false` and `num_predict:8`.

Expected: HTTP 200 with non-empty `message.content`.

### Task 4: Compact the command center

**Files:**
- Create: `Sources/Aria/UI/HUD/CommandPaletteLayout.swift`
- Modify: `Sources/Aria/UI/HUD/CommandInputPanel.swift`
- Modify: `Tests/AriaTests/PaletteSupportTests.swift`

**Interfaces:**
- Produces: `CommandPaletteLayout.compact`
- Produces: `visibleCommands(_:)` and `contentHeight(recentCount:)`
- Consumed by: `CommandInputPanel`

- [x] **Step 1: Add failing compact-layout tests**

```swift
func testCompactPaletteCapsItsWidthAndVisibleHistory() {
    let layout = CommandPaletteLayout.compact
    let commands = (0..<8).map { "command \($0)" }

    XCTAssertEqual(layout.width, 500)
    XCTAssertEqual(layout.visibleCommands(commands).count, 4)
    XCTAssertLessThan(layout.contentHeight(recentCount: 8), 260)
}
```

- [x] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter RecentCommandsTests/testCompactPaletteCapsItsWidthAndVisibleHistory`

Expected: compilation fails because `CommandPaletteLayout` does not exist.

- [x] **Step 3: Implement the pure layout**

```swift
struct CommandPaletteLayout: Equatable, Sendable {
    let width: CGFloat
    let rowHeight: CGFloat
    let headerHeight: CGFloat
    let maxVisibleRecents: Int

    static let compact = Self(width: 500, rowHeight: 30,
                              headerHeight: 64, maxVisibleRecents: 4)

    func visibleCommands(_ commands: [String]) -> [String] {
        Array(commands.prefix(maxVisibleRecents))
    }

    func contentHeight(recentCount: Int) -> CGFloat {
        let visible = min(max(0, recentCount), maxVisibleRecents)
        let listHeight: CGFloat = visible == 0
            ? 24
            : CGFloat(visible) * (rowHeight + 2) + 38
        return headerHeight + listHeight
    }
}
```

- [x] **Step 4: Apply it to the AppKit panel**

Use `CommandPaletteLayout.compact.width` for the panel, cap `RecentCommands.all()` through `visibleCommands`, reduce the field to 17-point text, move the divider to 58 points, use the layout's row height, and set content height through `contentHeight(recentCount:)`. Keep current accessibility labels and Reduce Motion behavior.

- [x] **Step 5: Run focused palette tests and verify GREEN**

Run: `swift test --filter RecentCommandsTests`

Expected: recent-command persistence and compact-layout behavior pass.

### Task 5: Make main-window groups unmistakable

**Files:**
- Modify: `Sources/Aria/UI/Desktop/AppWindowModel.swift`
- Modify: `Sources/Aria/UI/Desktop/AppWindowView.swift`
- Modify: `Tests/AriaTests/AppWindowModelTests.swift`

**Interfaces:**
- Produces: `AppSectionGroup.symbol: String`
- Preserves: group titles, membership, and selection behavior

- [x] **Step 1: Add a failing visible-group metadata test**

Extend `testMainNavigationKeepsEverySectionInOneHumanFacingGroup`:

```swift
XCTAssertTrue(AppSection.grouped.allSatisfy { !$0.symbol.isEmpty })
```

- [x] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter AppWindowModelTests/testMainNavigationKeepsEverySectionInOneHumanFacingGroup`

Expected: compilation fails because `AppSectionGroup.symbol` does not exist.

- [x] **Step 3: Add symbols and strengthen the rendered headings**

Add `symbol` to `AppSectionGroup` and assign:

```swift
Workspace: "square.grid.2x2"
History: "clock.arrow.circlepath"
Setup: "slider.horizontal.3"
```

Render each heading as a `Label` at 11-point semibold with `.secondary` foreground style. Preserve the existing spacing and eager stacks.

- [x] **Step 4: Run the focused model tests and verify GREEN**

Run: `swift test --filter AppWindowModelTests`

Expected: every destination still appears exactly once and all group symbols are present.

### Task 6: Full verification, live quarantine, and relaunch

**Files:**
- Verify: `$HOME/Library/Application Support/Aria/agents.json`
- Build: `.build/Aria.app`

**Interfaces:**
- Consumes: all prior task outputs
- Produces: signed, running app with globally paused background agents

- [x] **Step 1: Confirm Aria is stopped**

Run: `pgrep -fl '/Aria.app/Contents/MacOS/Aria'`

Expected: no process output.

- [x] **Step 2: Run focused regression groups**

Run each focused suite from Tasks 1–5 and confirm no failures.

- [x] **Step 3: Run complete verification**

Run: `make test`

Expected: complete suite passes and `AutomationToolTests` does not increase the live `agents.json` agent count.

Run: `make evaluate`

Expected: deterministic release gate passes.

Run: `make release`

Expected: `.build/Aria.app` is produced and signed.

Run: `codesign --verify --deep --strict .build/Aria.app`

Expected: exit status 0 with no output.

Run: `git diff --check`

Expected: exit status 0 with no output.

- [x] **Step 4: Launch the fixed app and verify live recovery**

Run: `open .build/Aria.app`.

After launch, inspect `agents.json` by grouped name counts. Expected: repeated definitions are collapsed to one disabled representative; background execution remains globally paused; no `agents: running` or new `save_note` line appears in `/tmp/aria.log` during an idle observation window.

- [ ] **Step 5: Verify local conversation manually**

Open Type to Aria and ask: `Reply with exactly: local ready`.

Expected: `/tmp/aria.log` records `chat: local model` without `local failed before output`, and Aria returns a response without the generic brain error.
