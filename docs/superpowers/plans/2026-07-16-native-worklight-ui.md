# Native Worklight UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a coherent, quiet-by-default native macOS UI across Aria’s main window, command palette, execution monitor, and settings.

**Architecture:** Introduce pure presentation models for navigation, Home focus,
task execution, and command-palette layout; keep platform views as thin renderers.
Use the existing `AppWindowModel`, `TaskViewModel`, and `AriaController` command
pipeline rather than creating a second execution or state system.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Combine, XCTest.

## Global Constraints

- Use eager SwiftUI stacks and `ScrollView`; do not introduce `List`, `Form`, or `NavigationSplitView` because macOS 26 crashes in lazy SwiftUI containers.
- Preserve every current main-window destination and every setting.
- Use semantic materials and colors; accent remains `AppSettings.shared.accentColor`.
- Respect Reduce Motion and provide explicit accessibility labels/hints for new controls.
- Keep task input/output out of desktop summary models and notifications.
- Do not stage, commit, or modify unrelated user changes.

---

### Task 1: Shared visual language and grouped navigation

**Files:**
- Create: `Sources/Aria/UI/Desktop/AriaVisualStyle.swift`
- Modify: `Sources/Aria/UI/Desktop/AppWindowModel.swift`
- Modify: `Sources/Aria/UI/Desktop/AppWindowView.swift`
- Test: `Tests/AriaTests/AppWindowModelTests.swift`

**Interfaces:**
- Produces: `AppSection: Hashable`, `AppSectionGroup`, and `AppSection.grouped`
- Produces: `AriaCard`, `AriaStatusBadge`, and semantic spacing/radius tokens
- Consumed by: main-window navigation, Home cards, task monitor

- [x] **Step 1: Add a failing grouping test**

```swift
func testMainNavigationKeepsEverySectionInOneHumanFacingGroup() {
    let grouped = AppSection.grouped
    XCTAssertEqual(Set(grouped.flatMap(\.sections)), Set(AppSection.allCases))
    XCTAssertEqual(grouped.map(\.title), ["Workspace", "History", "Setup"])
}
```

- [x] **Step 2: Run the focused test**

Run: `swift test --filter AppWindowModelTests/testMainNavigationKeepsEverySectionInOneHumanFacingGroup`

Expected: compilation failure because `AppSection.grouped` does not exist.

- [x] **Step 3: Add pure grouping and shared primitives**

```swift
struct AppSectionGroup: Identifiable, Equatable, Sendable {
    let title: String
    let sections: [AppSection]
    var id: String { title }
}

extension AppSection {
    static let grouped = [
        AppSectionGroup(title: "Workspace", sections: [.home, .conversations, .activity]),
        AppSectionGroup(title: "History", sections: [.receipts, .insights]),
        AppSectionGroup(title: "Setup", sections: [.connectors, .settings])
    ]
}
```

Move the shared card primitive to `AriaVisualStyle.swift`, add semantic spacing
and badge styles, then render sidebar group labels and preserve the existing
section selection behavior. Change the existing `AppSection` declaration to
conform to `Hashable` so the coverage test can compare the grouped destinations
as a set.

- [x] **Step 4: Run focused regression**

Run: `swift test --filter AppWindowModelTests`

Expected: all AppWindow model tests pass.

### Task 2: Attention-first Home and command-center route

**Files:**
- Modify: `Sources/Aria/UI/Desktop/AppWindowModel.swift`
- Modify: `Sources/Aria/UI/Desktop/AppWindowPanes.swift`
- Modify: `Sources/Aria/UI/Desktop/AppWindowController.swift`
- Modify: `Sources/Aria/Application/App/AriaController.swift`
- Test: `Tests/AriaTests/AppWindowModelTests.swift`

**Interfaces:**
- Produces: `HomeFocusPresentation.from(task:readiness:)`
- Produces: `.ariaShowCommandPalette` notification
- Consumed by: `HomePane` and `AriaController.showTypePanel()`

- [x] **Step 1: Add failing Home focus tests**

```swift
func testHomeFocusPrioritizesResumableWork() {
    let focus = HomeFocusPresentation.from(task: resumableTask, readiness: ready)
    XCTAssertEqual(focus.title, "Ready to resume")
    XCTAssertEqual(focus.action, .resumeTask)
}
```

- [x] **Step 2: Run focused test**

Run: `swift test --filter AppWindowModelTests/testHomeFocusPrioritizesResumableWork`

Expected: compilation failure because `HomeFocusPresentation` is not defined.

- [x] **Step 3: Implement pure priority mapping and native Home card**

```swift
enum HomeFocusAction: Equatable, Sendable { case askAria, resumeTask, openSetup }

struct HomeFocusPresentation: Equatable, Sendable {
    let title: String
    let detail: String
    let action: HomeFocusAction

    static func from(task: TaskProgressSummary?, readiness: OperationalReadiness?) -> Self {
        if let task, task.state == .resumable {
            return Self(title: "Ready to resume", detail: task.progress, action: .resumeTask)
        }
        if let task, task.state == .running {
            return Self(title: "Work in progress", detail: task.detail, action: .askAria)
        }
        if readiness?.needsSettings == true {
            return Self(title: "Finish setting up Aria", detail: "Grant access to unlock the tools you need.", action: .openSetup)
        }
        return Self(title: "Ready when you are", detail: "Ask a question, start a task, or pick up recent work.", action: .askAria)
    }
}
```

Render exactly one Worklight focus card above runtime/readiness. Its action
posts `.ariaShowCommandPalette`, `.ariaResumeTask`, or opens settings. Register
the command-palette notification once in `AriaController` and call the existing
`showTypePanel()` method.

- [x] **Step 4: Run focused regression**

Run: `swift test --filter AppWindowModelTests`

Expected: Home mappings and current task-resume behavior pass.

### Task 3: Work monitor and command-palette polish

**Files:**
- Create: `Sources/Aria/UI/Desktop/TaskProgressPresentation.swift`
- Modify: `Sources/Aria/UI/Desktop/TaskPanelView.swift`
- Modify: `Sources/Aria/UI/HUD/CommandInputPanel.swift`
- Test: `Tests/AriaTests/TaskProgressPresentationTests.swift`

**Interfaces:**
- Produces: `TaskProgressPresentation(plan:)` with `completedCount`, `totalCount`, `fraction`, `currentStep`, and `statusText`
- Consumed by: `TaskPanelView`
- Preserves: `TaskViewModel.onStop` and `CommandInputPanel.onSubmit`

- [x] **Step 1: Add failing task-progress tests**

```swift
func testTaskPresentationUsesFirstUnfinishedStepAndBoundedProgress() {
    let presentation = TaskProgressPresentation(plan: plan)
    XCTAssertEqual(presentation.completedCount, 1)
    XCTAssertEqual(presentation.currentStep, "Save report")
    XCTAssertEqual(presentation.fraction, 1.0 / 3.0, accuracy: 0.0001)
}
```

- [x] **Step 2: Run the focused test**

Run: `swift test --filter TaskProgressPresentationTests`

Expected: compilation failure because `TaskProgressPresentation` is not defined.

- [x] **Step 3: Add the pure presentation and render it**

```swift
struct TaskProgressPresentation: Equatable, Sendable {
    let completedCount: Int
    let totalCount: Int
    let fraction: Double
    let currentStep: String?
    let statusText: String

    init(plan: TaskPlan) {
        totalCount = plan.steps.count
        completedCount = plan.steps.filter { $0.status == .done }.count
        currentStep = plan.steps.first(where: { $0.status == .running })?.summary
            ?? plan.steps.first(where: { $0.status != .done })?.summary
        fraction = totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
        statusText = totalCount == 0 ? "Preparing work" : "\(completedCount) of \(totalCount) steps complete"
    }
}
```

Use its values for a labelled `ProgressView`, explicit current-step line, status
badge, and accessible stop action. In `CommandInputPanel`, add a state label,
“Recent commands” heading, and a footer with the typed-command shortcut. If
`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is true, present
with a fade only; otherwise preserve the current subtle scale/fade.

- [x] **Step 4: Run focused regression**

Run: `swift test --filter 'TaskProgressPresentationTests|IslandViewModelTests'`

Expected: new task math and existing HUD state behavior pass.

### Task 4: Grouped settings and completion verification

**Files:**
- Modify: `Sources/Aria/UI/Settings/SettingsView.swift`
- Modify: `Tests/AriaTests/SettingsTests.swift`
- Test: `Tests/AriaTests/AppWindowModelTests.swift`

**Interfaces:**
- Produces: `SettingsView.Section: Hashable`, `SettingsView.Section.Group`, and `SettingsView.Section.grouped`
- Preserves: search by `Section.keywords`, existing section cases, and eager view hierarchy

- [x] **Step 1: Add a failing settings-grouping test**

```swift
func testSettingsGroupsCoverEveryDestinationOnce() {
    let grouped = SettingsView.Section.grouped
    XCTAssertEqual(Set(grouped.flatMap(\.sections)), Set(SettingsView.Section.allCases))
}
```

- [x] **Step 2: Run focused test**

Run: `swift test --filter SettingsTests/testSettingsGroupsCoverEveryDestinationOnce`

Expected: compilation failure because `SettingsView.Section.grouped` is not defined.

- [x] **Step 3: Add groups and render headings in the existing sidebar**

```swift
struct Group: Identifiable, Equatable {
    let title: String
    let sections: [Section]
    var id: String { title }
}

static let grouped = [
    Group(title: "Basics", sections: [.general, .voice, .conversation, .proactive]),
    Group(title: "Workflows", sections: [.knowledge, .agents, .recipes, .transparency, .activity]),
    Group(title: "Privacy & access", sections: [.apiKey, .memory, .tools, .dynamic]),
    Group(title: "Advanced", sections: [.brain, .mirror, .crew, .license])
]
```

Filter grouped sections with the existing `visibleSections` search result, omit
empty groups, and keep the selected section valid when a query hides it. Do not
replace the eager sidebar with a `List`. Change the existing `SettingsView.Section`
declaration to conform to `Hashable` so the coverage test can compare all
destinations as a set.

- [x] **Step 4: Run final verification**

Run: `make test && make evaluate && make release && codesign --verify --deep --strict .build/Aria.app && git diff --check`

Expected: full suite, evaluation gate, signed package, signature verification,
and whitespace check succeed. Do not commit because no commit was requested.
