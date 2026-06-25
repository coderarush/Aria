# Aria Live Loop — Design

**Status:** Design approved (conversation 2026-06-24). Ready for implementation plan.
**Date:** 2026-06-24.
**Branch:** `runtime-os`.
**Builds on:** [2026-06-09 V9 Proactive Presence](2026-06-09-aria-v9-proactive-presence-design.md) and the runtime-os Presence/Perception layers. Strictly additive.

## North star this serves

CLAUDE.md: *"Users stop thinking 'I should open App X' and think 'I should ask Aria.'"*
The next step past that is: users stop reaching for Aria at all, because she already
did the thing. This is the Siri→JARVIS leap — the agent loop running **continuously and
ambiently** instead of only when summoned.

## Problem

Aria has every JARVIS organ but they don't form a living loop:

- **Perceive** exists (`Perception/Engine/PerceptionEngine`, `ObservationBus`,
  EventKit, AX/screen/OCR vision) but only produces observations.
- **Anticipate** exists (`Presence/Detection/OpportunityDetector` +
  `OpportunityRule.evaluate(context) -> Opportunity?`, `OpportunityRanker`,
  `ProactiveEngine.tick`) but an `Opportunity` is scores + text only.
- **Act** is the missing organ. `Opportunity` and `PresenceSuggestion` carry **no
  executable action**. Proactivity dead-ends at "here's a suggestion string."
- **Remember** exists (`Memory/Store/MemoryGraph`, `LongTermMemory`) but proactive
  outcomes don't feed it, so there's no continuity loop.

Nothing wires these into one always-on cycle, and the anticipate layer can't act. So
Aria is reactive: she waits to be asked.

## Goal

A **Live Loop**: an always-on runtime that drives a real
**Perceive → Anticipate → Act → Remember** cycle. It feeds live context into the
existing recognizer/ranker layer, attaches an **executable Playbook** to each
opportunity, runs the top playbook under a **per-playbook autonomy gate** (auto for
read-only/prep, confirm for anything outward), records the outcome to memory, and
surfaces everything ambiently through the existing blob/HUD. Four recognizers ship on
it. The loop is generic; recognizers and playbooks are pluggable, so widening later is
additive.

## Non-goals (v1)

- Not learning that auto-promotes autonomy tiers (tiers are user-set; learning only
  informs ranking/content).
- Not multi-device handoff, hardware, or Glass.
- Not removing the destructive-action gate — every outward/mutating action still passes
  `Permissions/Policy/Safety` and still confirms before Send/Pay/Delete/Create.
- Not a notification-spam system — at most one live proactive card at a time, TTL
  expiry, snooze/never honored.

## Architecture

All new code is additive on `runtime-os`. Existing types reused as-is unless noted.

### 1. `LiveLoop` runtime *(new — `Presence/Live/LiveLoop.swift`)*
The always-on coordinator (actor). Responsibilities:
- Subscribe to signal sources; maintain a current `PresenceContext`
  (`Presence/Detection/OpportunityDetector.swift` already defines it).
- Run on **events + a low-frequency idle tick** (~30–60s), never a hot loop.
- On each evaluation: build context → `OpportunityDetector.detect` →
  `OpportunityRanker` → take top opportunity → if its `Playbook` tier permits and it
  isn't snoozed/duplicate, dispatch it → record outcome → update memory → surface.
- Honors a global pause flag and per-recognizer enable flags
  (extend `Presence/Detection/ProactiveSettings.swift`).
- Battery/low-power aware pause (optional, setting-gated).

### 2. Signals (Perceive) *(new adapters — `Presence/Live/Signals/`)*
Cheap, local-first producers that update `PresenceContext` and/or publish to
`ObservationBus`:
- `CalendarSignal` — EventKit (`Execution/Actions/EventKitTools.swift`); next-event +
  minutes-until.
- `MailSignal` — new/important mail or notification observation.
- `ScreenActivitySignal` — AX frontmost + screen-diff + on-device OCR (existing vision
  path); detects friction/repetition, idle seconds.
- `ClockSignal` — time-of-day / first-unlock for the daily brief.

LLM is **not** called here. Detection is local; reasoning happens only inside a
playbook once a recognizer fires.

### 3. Recognizers (Anticipate) *(new — `Presence/Live/Recognizers/`)*
Each conforms to the existing `OpportunityRule` protocol
(`evaluate(_ context: PresenceContext) -> Opportunity?`) and is registered via
`OpportunityDetector.addRule`. **Change:** `Opportunity` gains an optional
`playbook: PlaybookRef` (an identifier + bound inputs), so a recognized opportunity
carries the action to take. Four ship in v1 (see table below).

### 4. Playbooks (Act) *(new — `Presence/Live/Playbooks/`)*
A `Playbook` is a named, multi-step action template plus an `AutonomyTier`. It executes
through the **existing live path** — `Execution/Executor/AgentOrchestrator` +
`AutonomyEngine` + the real `ToolRegistry` tools — so there is no second execution
engine and no new orphan code. A `PlaybookRunner` resolves a `PlaybookRef` to steps,
binds inputs from context/memory, and runs them.

### 5. Autonomy gate
Per-playbook `AutonomyTier`: `auto` (read-only/prep — gather, brief, open),
`confirm` (outward/mutating — send, create, pay), `off`. Maps onto the existing
`Permissions/Policy/AutonomyLevel` (`.execute`/`allowsExecution`). `Safety` still vets
**every** tool call regardless of tier. Tier is user-tunable per recognizer in Settings.

### 6. Surface (UX)
Reuse the ambient blob/HUD (`UI/HUD/PresenceRuntime`, `PresenceChoreographer`) and the
existing `SuggestionEngine`/`SuggestionPresenter`. The blob signals "noticed something"
(non-modal); expanding shows a proactive card with **approve / edit / dismiss / snooze /
never**. `confirm`-tier playbooks pause at the card before acting; `auto`-tier playbooks
act and the card reports what was done. A "what Aria did/considered" activity log
(reuse `TrustDashboard`).

### 7. Remember
Every cycle writes an outcome record (opportunity, playbook, accept/dismiss/auto-ran,
result) to `MemoryGraph`/`LongTermMemory`, plus learned preferences (your reply style,
"always skip standup prep", recurring attendees). This continuity feeds the next cycle's
context and ranking. Reuses `ProactiveEngine.record`/`OutcomeStore` patterns.

## The four recognizers (v1)

| Recognizer | Signal trigger | Playbook | Tier |
|---|---|---|---|
| `MeetingPrepRule` | event T-15m (CalendarSignal) | pull last thread + related notes/docs + attendee memory → spoken brief + open notes | `auto` |
| `InboxTriageRule` | new important mail (MailSignal) | classify + draft reply in your style → card | `confirm` |
| `ScreenCoPilotRule` | detected friction/repetition (ScreenActivitySignal) | offer/do next step via `show_me`/walkthrough | `confirm` |
| `DailyBriefRule` | morning / first unlock (ClockSignal) | synthesize calendar+mail+reminders+yesterday's threads → spoken brief + card | `auto` |

## Data flow

```
signal event ──▶ update PresenceContext ──▶ OpportunityDetector.detect (local, cheap)
   ▲                                              │
   │                                              ▼
   │                                        OpportunityRanker ──▶ top Opportunity(+PlaybookRef)
   │                                              │
   │              snoozed / duplicate / tier=off? │ yes ──▶ drop
   │                                              │ no
   │                                              ▼
   │                          tier=auto ──▶ PlaybookRunner (AgentOrchestrator+Safety) ──▶ act
   │                          tier=confirm ──▶ proactive card ──(approve)──▶ act
   │                                              │
   └────────── memory + context update ◀── record outcome (MemoryGraph) ◀── result + surface
```

Cadence: evaluate on signal events + a ~30–60s idle tick. LLM calls happen only inside a
fired playbook. One live proactive card at a time; TTL expiry.

## Guardrails / cost / privacy

- Local-first detection; LLM gated to fired playbooks; cadence-limited; battery-aware
  pause optional.
- Every outward action confirm-tier + `Safety`-vetted.
- Global "pause Aria" + per-recognizer toggles + full activity log.
- Nothing leaves the device beyond the model call that already happens (honors
  "100% local except voice").

## Scope of the first implementation plan

Build: `LiveLoop` runtime, the four signal adapters, the recognizer/playbook framework
(`Opportunity.playbook`, `Playbook`/`PlaybookRef`/`PlaybookRunner`, `AutonomyTier`), the
autonomy gate, the proactive-card surface wiring, and all four recognizers — wired
**live** on `runtime-os` through the existing orchestrator/tools.

Explicitly **out** of v1: tier-promoting learning, multi-device, hardware/Glass.

## Testing

- **TDD, pure logic:** each `OpportunityRule.evaluate` (fixture `PresenceContext` →
  expected `Opportunity` + `PlaybookRef`); `PlaybookRunner` step resolution + input
  binding; `LiveLoop` scheduler (event/tick → evaluate, dedup, snooze, single-card);
  autonomy gate (auto vs confirm vs off → execute/park).
- **Outcome/memory:** record writes the expected MemoryGraph entry; continuity reads it
  back into context.
- **Live smoke (flagged — GUI/perception can't run headless):** real calendar event
  fires MeetingPrep; real new mail fires InboxTriage draft; screen friction fires
  CoPilot; morning fires DailyBrief; confirm-tier pauses at card; auto-tier acts;
  global pause + per-recognizer toggles honored. Requires the installed signed app for
  EventKit/AX/Automation permissions (like prior EventKit/computer-use validation).

## Open risks

- Perception/AX/EventKit permissions only land on the signed installed app, not
  `make run` — live validation gated on a built `.app` (known pattern).
- Friction/repetition detection (ScreenCoPilot) is the fuzziest trigger; v1 uses
  conservative heuristics (repeated identical error text / repeated manual step) to
  avoid false fires; tune live.
- Cadence/battery tuning is empirical; ship conservative defaults, expose knobs.
