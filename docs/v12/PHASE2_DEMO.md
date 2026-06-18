# Aria Phase 2 — Context → Intent → Presence (Demo + Architecture)

Branch: `aria-omega-levers`. Status of each phase, the end-to-end demo flow, and
how to measure it on device. Nothing here is fabricated — components marked
**(built, inert)** are tested but not yet wired into the live command flow.

## What shipped this phase

| Phase | Component | Files | State |
|---|---|---|---|
| Bug | Learning gate reads real outcome | `Models.swift`, `AgentOrchestrator.swift`, `AriaController.swift` | **wired** |
| Bug | No unattended/reentrant confirmation modal | `ConfirmationPolicy.swift`, `AriaController.swift`, `HotkeyTap.swift` | **wired** |
| Bug | Focus seed can't clobber fresher activation | `AppFocusMonitor.swift` | **wired** |
| P1 | `ContextCoordinator` world model | `Core/Context/CurrentWorldState.swift`, `ContextCoordinator.swift` | **built, inert** |
| P2 | `IntentEngine` world-aware re-ranker | `Core/Proactive/IntentEngine.swift` | **built, inert** |
| P3 | `SessionMemory` continuation | `Core/Memory/SessionMemory.swift` | **built, inert** |
| P5 | `TrustProfile` adaptive autonomy | `Core/Autonomy/TrustProfile.swift` | **built, inert** |
| P4 | PresenceCoordinator | — | **not built — already exists** (`PresenceChoreographer` + `IslandViewModel.State`) |

"Inert" = pure/tested, callable, but not yet read by the live flow, so it changes
no behavior. Wiring each is one small additional commit (see Next).

## Target demo flow

1. **Invoke** — `⌥⌥` (double-tap Option) → command palette. *(wired)*
2. **"Continue Aria"** — `SessionMemoryStore.latest(project:)` returns the last
   snapshot (goal / progress / blockers / nextStep) → spoken resume line via
   `resumeDigest()`. *(needs wiring: record snapshots on task completion + read
   on summon)*
3. **Restore context** — `ContextCoordinator.worldState()` merges active app +
   focus duration + clipboard + recent work into one snapshot injected into the
   system prompt. *(P1 built; focus line already injected via AppFocusMonitor)*
4. **Suggest next** — `IntentEngine.rank(candidates, world:)` re-ranks proactive
   candidates by the active app. *(P2 built; candidates come from ProactiveEngine)*
5. **Act with the right autonomy** — `TrustProfile.advisedLevel(...)` decides
   auto / suggest / ask per action, dropping unreliable automations to suggest.
   *(P5 built)*
6. **Run / diff / approve / commit** — existing autonomy engine (plan → execute →
   verify → recover) + the now-correct destructive confirmation. *(wired)*

## Architecture notes (reuse-first)

- No new source of truth. `ContextCoordinator` is a read-only aggregator over
  `AppFocusMonitor` / `ClipboardContext` / `WorkJournal`; `IntentEngine` re-ranks
  `ProactiveEngine` candidates; `TrustProfile` composes `ActionImportance` +
  `ConfirmationPolicy` + the learned `successRatio`. None reimplement those.
- `SessionMemory` is the one genuinely-new store — it carries the live
  goal/blockers/nextStep that `WorkJournal` (completed work) doesn't.
- The reliability fixes close a real hole: automations now record true success,
  and a destructive confirmation never fires unattended or stacks re-entrantly.

## Measuring (on device — not run here)

```bash
make release && open .build/Aria.app
```
Timings the spec asks for must be measured live (this environment can't run the
app). Suggested probes: time-to-first-token (`Log.trace "turn: streaming…"`),
worldState() assembly cost, confirmation round-trip. No numbers are invented here.

## Next (wiring, each a small commit)

1. Record a `SessionSnapshot` on task completion (hook `AutonomyEngine.finished`).
2. Read `SessionMemoryStore.resumeDigest()` in the briefing / first summon.
3. Inject `ContextCoordinator.summaryLine()` into the system prompt (superset of
   the focus line already injected).
4. Consult `TrustProfile.advisedLevel` at the proactive auto-act gate.
