# Aria V9 — Proactive Presence Engine (Design)

**Status:** V9 pre-release design.
**Date:** 2026-06-09.
**Supersedes nothing.** Strictly additive to the V8 Learning/PatternEngine path.

## North star this serves

CLAUDE.md: *"Users stop thinking 'I should open App X' and think 'I should ask Aria.'"*
This feature closes the last gap toward that: Aria stops waiting to be asked. She
anticipates the moment and offers — gently, before you reach for the app yourself.

## Problem

Proactivity exists today but is thin and un-JARVIS:

- The only learned signal is app launch/quit plus recorded commands
  (`Core/Learning/PatternEngine.swift`, fed by `observeAppEvents()` in
  `App/AriaController.swift`).
- Detection runs on a blunt hourly `Timer` (`learningTimer`, 3600s).
- Suggestions surface through a **blocking modal** (`presentSuggestion` →
  `Self.confirm`), which hijacks the screen — the opposite of an ambient presence.

Everything else in Aria (voice, computer-use, autonomy, memory, resumable tasks) is
mature. Ambient anticipation is the single highest-leverage step toward a JARVIS-grade
feel, and the current path is the weakest mature subsystem.

## Goal

A **Proactive Presence engine**: Aria anticipates from multiple signal sources, ranks
candidate suggestions, and surfaces the best one **silently via the orb**, speaking only
when the user glances at her or wakes her. She learns from accept/dismiss. Fully additive;
the existing PatternEngine and orb brand are preserved.

## Non-goals

- Not replacing PatternEngine — it becomes a backend for two providers.
- Not a notification-spam system — at most one live suggestion at a time, expiring TTL.
- Not changing destructive-action gating — proactive actions still pass `Safety` and still
  confirm before Send/Pay/Delete.
- Not a new visual identity — the orb gains one additive state, nothing is swapped.

## Architecture

New subsystem under `Sources/Aria/Core/Proactive/`.

```
ProactiveEngine (actor)         ranks, dedupes, decides if/when to surface
  ├─ SignalProvider (protocol)  candidates(context) async -> [Suggestion]
  │   ├─ CalendarSignalProvider   EventKit upcoming events
  │   ├─ RoutineSignalProvider    wraps existing PatternEngine app-routines
  │   ├─ CommandSignalProvider    recurring recorded commands  (Phase 2)
  │   └─ ScreenSignalProvider     focused app + selection, relevance-gated (Phase 2)
  ├─ ProactiveScheduler          event-driven + light poll
  └─ SuggestionPresenter         silent orb glow -> speaks on glance
```

### Components

**`Suggestion`** (value type)
- `id: UUID`
- `source: SuggestionSource` (`.calendar`, `.routine`, `.command`, `.screen`)
- `spokenLine: String` — the one-line offer Aria says ("Standup in five — open the notes doc?")
- `action: SuggestionAction` — `.runCommand(String)` | `.runIntent(...)` | `.offerAutomation(BehaviorPattern)`
- `confidence: Double` (0–1)
- `urgency: Urgency` (`.timeCritical` | `.ambient`)
- `createdAt: Date`, `expiry: Date`
- `dedupeKey: String` — stable per recurring suggestion, used for feedback + suppression

**`SignalProvider`** (protocol)
- `func candidates(now: Date, context: ProactiveContext) async -> [Suggestion]`
- `var source: SuggestionSource { get }`
- `var isEnabled: Bool { get }` — driven by settings
- Each provider is independently testable with injected inputs (no global state).

**`CalendarSignalProvider`**
- Reads upcoming EventKit events via the existing EventKit access (`Tools/System/EventKitTools.swift`).
- Emits a `.timeCritical` suggestion in a lead window (default 5 min) before an event:
  offers the user's typical prep for that event when known (link/doc/app), else a plain
  "Your <title> starts in N minutes."
- Dedupe key = event identifier; one offer per event.

**`RoutineSignalProvider`**
- Thin wrapper over `PatternEngine.patternsToSuggest()` / `automationsToFire()`.
- Converts a `BehaviorPattern` into a `Suggestion` (`.ambient`, `action = .offerAutomation`).
- Preserves the existing approve/suppress/defer semantics by delegating back to PatternEngine.

**`ProactiveEngine`** (actor)
- Holds the enabled providers.
- `func tick(now:context:) async -> Suggestion?` — gathers candidates from all enabled
  providers, filters expired/suppressed/quiet-hours, ranks by `(urgency, confidence,
  recency)`, dedupes by `dedupeKey`, returns at most the single best live suggestion.
- `func record(outcome: SuggestionOutcome)` — `.accepted` | `.dismissed` | `.expired`,
  keyed by `dedupeKey`/source; updates the feedback store.
- Never surfaces a suggestion whose `dedupeKey` is currently suppressed (N dismissals).

**`ProactiveScheduler`**
- Replaces the single blunt hourly timer with:
  - **Calendar wakeups** — schedule a check ~lead-window before each upcoming event.
  - **App-event driven** — existing `observeAppEvents()` triggers a routine re-check (debounced).
  - **Focus-change driven** (Phase 2) — debounced + `ContextRelevance`-gated screen checks.
  - **Periodic sweep** — a low-frequency fallback pass (keeps routine detection alive).
- On each trigger: call `ProactiveEngine.tick`; if it returns a suggestion, hand to the presenter.

**`SuggestionPresenter`** (MainActor)
- On a new suggestion: put the orb into a new **additive** `hasSuggestion` state on
  `IslandViewModel` — a calm glow/pulse, **silent**. Stores the pending suggestion.
- **Reveal triggers:** user clicks/glances at the orb, or wakes Aria. Then Aria speaks
  `spokenLine` and listens for a short accept window.
  - Affirmative ("yeah", "do it", "sure") → run `action` through the orchestrator/Safety gate.
  - Negative or no response within window → mark `.dismissed`, clear orb state.
- **Auto-expire:** if untouched past `expiry`, mark `.expired`, clear orb state silently.
- **Never blocks.** The modal `Self.confirm` path is retained only for destructive
  confirmations downstream of an accepted action.

### Feedback loop

A small `ProactiveStore` (mirrors `LearningSettings` persistence via
`Core/PersistencePaths.swift`):
- Counts accept/dismiss/expire per `dedupeKey` and per `source`.
- Suppresses a `dedupeKey` after N consecutive dismissals (default 3).
- Decays suppression over time so a once-rejected suggestion can return later if the
  user's behavior changes.

### Safety & privacy

- Proactive actions execute through the existing orchestrator and `Safety` gates;
  destructive actions (Send/Pay/Delete) still require explicit confirmation.
- **Quiet hours** and macOS Do-Not-Disturb are respected (no surfacing during).
- Master "Proactive" toggle plus per-source toggles in `SettingsView`.
- **ScreenSignalProvider is OFF by default** (reads focused content) — opt-in only.
- Consistent with V8: every fired/accepted action lands in the durable Activity Log.

## Data flow

1. A trigger fires (calendar wakeup / app event / sweep).
2. `ProactiveScheduler` calls `ProactiveEngine.tick`.
3. Engine gathers candidates from enabled providers, ranks, dedupes, applies suppression
   + quiet-hours, returns at most one `Suggestion`.
4. `SuggestionPresenter` puts the orb into the silent `hasSuggestion` glow.
5. User glances/wakes → Aria speaks the offer → accept runs the action (via Safety),
   ignore/expire clears it.
6. Outcome recorded in `ProactiveStore`; feedback shapes future ranking/suppression.

## Error handling

- A provider that throws or times out is skipped for that tick (engine never blocks on one
  source). Logged via `Utilities/Logger.swift`.
- Missing EventKit permission → CalendarSignalProvider yields nothing, no error surfaced.
- Action execution failure surfaces through the normal orchestrator error path (spoken +
  Activity Log), same as a user-initiated command.

## Testing

Repo tests heavily (`make test`, ~166 tests). Add:
- `ProactiveEngineTests` — ranking, dedupe, suppression after N dismissals, quiet-hours
  filtering, single-best-suggestion selection, expiry filtering. Inject `now` + fake providers.
- `CalendarSignalProviderTests` — lead-window emission, dedupe per event, no-permission case.
- `RoutineSignalProviderTests` — BehaviorPattern → Suggestion mapping; approve/suppress
  delegate back to PatternEngine.
- `ProactiveStoreTests` — accept/dismiss/expire accounting, suppression + decay.
- Presenter logic covered by a thin testable seam (state transitions on accept/dismiss/expire),
  keeping AppKit/voice side effects behind an injected interface.

All new logic injects `Date`/inputs so tests are deterministic (matches existing repo style,
e.g. `AXGeometryTests`).

## Phasing

**Phase 1 (this spec, ships first):**
- `Core/Proactive/`: `ProactiveEngine`, `SignalProvider`, `Suggestion`, `ProactiveScheduler`,
  `SuggestionPresenter`, `ProactiveStore`.
- Providers: **Calendar** + **Routine** (routine = refactor of current modal path into ambient).
- Orb `hasSuggestion` state (additive) + silent-glow/speak-on-glance delivery.
- Feedback loop + suppression. Settings toggles (master + per-source; quiet hours).
- Full test coverage above for shipped components.
- Removes the blocking-modal suggestion delivery in favor of ambient (the underlying
  PatternEngine approve/suppress semantics are preserved).

**Phase 2 (follow-on, own spec + plan):**
- **Command** + **Screen** providers (screen relevance-gated, OFF by default).
- Confidence/urgency tiering refinements; quiet-hours polish; focus-change scheduling.

## Preservation checklist (CLAUDE.md)

- PatternEngine: preserved, wrapped, not replaced.
- Orb/blob brand: one additive state, no swap, no removed animations.
- Modal confirm: retained for destructive confirmations.
- Existing approve/suppress/defer automation semantics: preserved via delegation.
- All actions remain visible in the Activity Log and pass Safety gates.
