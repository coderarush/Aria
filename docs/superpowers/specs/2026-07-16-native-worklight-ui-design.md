# Native Worklight UI Design

## Goal

Unify Aria’s desktop window, command palette, execution panel, and settings
into a calm, native macOS experience that is quiet when idle and unmistakably
clear when Aria is working.

## Product decision

Aria is a quiet-by-default assistant with an on-demand command center. The
command palette and HUD remain the fastest way to invoke it. The desktop window
is where a user intentionally reviews current work, history, readiness, and
configuration. It will not become a permanently demanding dashboard.

## Visual direction: Native Worklight

The visual language uses macOS semantic materials and system typography so it
adapts correctly to light mode, dark mode, accessibility contrast, and the
user-selected accent. The signature element is a narrow **Worklight**: a
restrained accent treatment that marks the current interaction state in the
palette, the Home focus card, and the execution panel. It is informative, not
decorative: green/neutral for ready, accent for active work, orange for a
resumable task, and red only for errors.

Typography remains SF Pro with rounded display treatment only for Aria’s
identity and major task titles. Functional labels use the standard system face.
The spacing rhythm is 4, 8, 12, 16, 24, and 32 points; corner radii are 10,
14, and 18 points. Materials, separators, and primary/secondary labels use
semantic system colors rather than fixed hexadecimal colors.

## Surface plan

### 1. Main window and Home

The sidebar becomes grouped navigation with an always-present “Ask Aria”
control. Home starts with a single **Now** focus card rather than a generic
greeting card: it states whether Aria is ready, actively working, or has a
resumable task; offers the relevant action; and keeps runtime/readiness detail
one level below. Existing conversations, activity, receipts, insights, and
connectors remain available and no existing destination is removed.

### 2. Command palette and HUD

The palette gains an explicit state label, a concise keyboard route, a recent
commands heading, and an outcome-aware footer. It stays an AppKit panel so the
existing global-hotkey, first-mouse, accessibility, and macOS 26 stability
workarounds are preserved. Motion respects macOS Reduce Motion: fades replace
scale/spring transforms.

### 3. Execution panel

The floating task panel becomes a compact work monitor: task status, completed
count, determinate progress, a clear current step, expandable result detail,
and a destructive Stop control separated from routine actions. It remains a
separate accessory panel and continues to use the existing `TaskViewModel` and
execution events; it does not duplicate autonomous execution logic.

### 4. Settings

Settings retains its eager VStack/ScrollView implementation because macOS 26
has a known SwiftUI lazy-container crash. Its sidebar gains human-facing groups
(Basics, Workflows, Privacy & access, Advanced) and clearer selected-state
treatment. Search remains cross-section and no setting is renamed or removed.

## Interaction and state flow

The main-window “Ask Aria” button posts a content-free notification. The
controller presents the existing `CommandInputPanel`, which feeds its existing
typed-command pipeline. Home derives a pure focus presentation from the
current task and operational-readiness snapshot. The task panel derives a pure
execution presentation from `TaskPlan` step status, then renders it without
retaining raw task input.

## Accessibility and resilience

All new buttons have explicit labels and hints. Reduce Motion is respected in
both SwiftUI and AppKit presentation paths. Color is never the only status
indicator. Views continue to avoid `NavigationSplitView`, `List`, and `Form`.
No screen content, task input, or model output is added to system
notifications.

## Verification

Pure models cover section grouping, Home focus mapping, execution progress, and
command-palette presentation. Existing model, task-store, settings, and HUD
tests remain regression coverage. The full suite, evaluation gate, packaged
app, signature check, and whitespace check are required before handoff.
