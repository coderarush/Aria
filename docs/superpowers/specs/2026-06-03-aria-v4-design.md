# Aria v4 — Autonomous Agent ("Thomas-style") — Design Spec

**Date:** 2026-06-03
**Status:** Approved (pending final spec review)
**Builds on:** Aria v3.0.0

## Summary

v4 turns Aria from a conversational assistant into an **autonomous agent**: give
her a multi-step goal and she **plans → executes → verifies → recovers** across
steps, dispatching work to a named crew of specialist sub-agents, all visible in
a live task panel + status line + voice narration. She runs **fully
autonomously** (only pausing to confirm clearly destructive actions), uses the
tools she already has (shell, AppleScript, web, code-gen), and — critically —
**always works on the free Gemini tier** via a request scheduler that paces
instead of failing.

## Roadmap context

End vision: personal JARVIS, eventually a sellable product. Pillar C ("do
anything / computer use") decomposes into versions:
- **v4 — Autonomy on existing tools** *(this spec)*: plan/execute/verify/recover
  with named sub-agents.
- **v5 — Generic computer use**: see + click + type any app (vision/accessibility).
- **v6 — Deeper integrations** + **reliability/polish**.

The deferred v3 bugs (second-wake re-arm; talk-over barge-in) are addressed here
(second-wake) or later (barge-in needs the AEC work, still blocked).

## Decisions (locked with user)

| Topic | Decision |
|-------|----------|
| v4 capability | Autonomy on Aria's existing tools (Thomas-style) |
| Architecture | Plan → Execute → Verify → Recover, **combined** with ReAct + hierarchical named sub-agents |
| Autonomy level | **Fully autonomous**; hard stop only for destructive/irreversible actions |
| Progress UX | Expandable **task panel** (checklist) + **voice narration** + **status line** |
| Sub-agent names | Cosmic crew: **Orion, Lyra, Atlas, Nova, Comet** (Aria = conductor) |
| Free tier | **Must always work free** — call-minimization + multi-bucket spread + pace-never-fail scheduler |
| Prerequisite | Fix the **second-wake** regression first |

## Non-Goals (out of v4)

- Generic computer use (vision/click any app) → **v5**.
- Deeper new app integrations beyond existing tools/AppleScript → v5/v6.
- Talk-over barge-in (needs hardware echo cancellation, still blocked) → later.
- Cross-session long-term memory → later.
- On-device LLM fallback → not needed (the scheduler covers free tier).

---

## Section 1 — Architecture & components

**New:**
- **`AutonomyEngine`** (Core) — orchestrator. Goal → Plan → Execute → Verify →
  Recover → progress events. The v3 streaming path stays for chat/quick actions;
  the engine handles multi-step goals.
- **`TaskPlan` / `TaskStep`** (models) — ordered steps; each has a description,
  an executor (a tool or a named sub-agent), status (`pending/running/done/failed`),
  and a result. This is the checklist the panel renders.
- **`Verifier`** — quick model check after each step (intent achieved?) →
  pass/retry/re-plan. Local-first (tool result) where possible.
- **`RequestScheduler`** (Core) — every model call routes through it; spreads
  across model buckets and paces under load (see Section 2b).
- **`TaskPanel`** (UI) + **`TaskViewModel`** — the live checklist card + Stop.

**Changed/extended:**
- **Named sub-agent crew** — evolve the existing `SubAgent` framework into a
  named registry with personas, specialties, and **scoped tool sets**, each
  running a capped ReAct loop. Roster: Orion, Lyra, Atlas, Nova, Comet.
- **Intent routing** (controller/orchestrator) — quick chat/action → v3 path; a
  real multi-step goal → `AutonomyEngine`.
- **Safety gate** — reuse v3's `confirmationHandler`; destructive actions confirm
  even when fully autonomous.
- **`WakeWordEngine`** — fix the second-wake regression (return to a clean wake
  state after every conversation/turn).

---

## Section 2 — The autonomy loop + safety

**Intent routing.** A quick check: simple chat/one-shot → v3 streaming path; a
real multi-step goal → `AutonomyEngine`.

**Loop:**
1. **Plan** — one model call (goal + screen-if-needed + tool/crew catalog) emits
   an ordered step list, each tagged with its executor. Renders immediately in
   the panel; she narrates the plan.
2. **Execute** — per step: a **tool** runs directly (no model call), or a **named
   sub-agent** is dispatched and runs its own capped ReAct loop. Live updates to
   status line, panel, and brief voice.
3. **Verify** — local-first (tool success/output); model verify only on genuinely
   ambiguous results. Pass → next; fail → Recover.
4. **Recover** — retry the step or re-plan remaining steps from current state
   (cap: 2 retries/step). Unrecoverable → stop + honest reason.
5. **Done** — result spoken; panel complete; plan + results kept in per-task
   memory for follow-ups.

**Safety floor (even fully autonomous):** destructive/irreversible actions —
delete, send, email, pay, overwrite (via `tool.isDestructive` + keyword
heuristic) — pause for a one-tap confirm.

**Bounds + control:** max ~12 steps + overall timeout; a **Stop** control (button
+ spoken "stop") cancels immediately (already-executed side-effects can't be
undone). One task at a time — a new goal asks to stop the current or queue.

## Section 2b — Free-tier guarantee (pace, never fail)

Free limit ≈ 20 requests/min **per model**. Three layers so a task always
completes free:

1. **Fewer model calls.** Deterministic steps (open app, known command, file/
   system ops, sending a pre-written draft) run as plain tool calls with **no**
   model round-trip. **Local-first verification** uses the tool's own success/
   output; the model verifier runs only on ambiguous results. Sub-agent ReAct
   loops are tightly capped. Net: a handful of calls per task, not dozens.
2. **Spread across every free bucket.** Each call routes to whichever Gemini
   model has capacity now — `flash`, `flash-lite`, `2.0-flash`, `2.0-flash-lite`,
   … (each has its own per-minute free quota) ≈ ~5× effective free rate.
3. **Pace, don't fail.** A `RequestScheduler` tracks each bucket's recent usage;
   when all are momentarily maxed it **queues the call and waits** (showing
   "pacing…") until a bucket frees, then proceeds. Tasks never error — they slow
   under load.

**Guarantee:** free tasks always finish; very heavy ones may pace (slower, never
broken). All model calls (chat, v3, v4) route through `RequestScheduler`, so the
whole app inherits the guarantee. Pacing affects speed only, never correctness.

## Section 3 — Named sub-agent crew

Each has a persona (narration flavor), a specialty (planner assignment), and a
**scoped tool set** (safety boundary). Each runs a **capped ReAct loop over only
its allowed tools**.

- **Orion** 🔭 — research & web. `web_search`, `web_fetch`.
- **Lyra** ✍️ — writing & drafting (emails, notes, docs, summaries).
  `write_file`, clipboard.
- **Atlas** 🔧 — system & apps. `shell`, `applescript`, `open_app`, file ops.
- **Nova** 🧩 — writes **and runs** code (dynamic code-gen factory).
- **Comet** ✉️ — messages & mail. Drafts freely; **sending is gated**
  (destructive → confirm). Mail/Messages AppleScript.

**Aria** is the conductor (plans, narrates, orchestrates). **Dispatch:** the
planner tags each step with a tool or a crew member by name; the Executor hands
sub-agent steps to that agent. **Scoping** keeps blast radius bounded (Orion
can't run shell; only Comet touches messaging, with confirm). The roster is an
extensible registry (new agents drop in; toggle any in Settings).

## Section 4 — Progress UI (panel + status + voice)

Three synced surfaces from one source of truth (`TaskViewModel` holding the
`TaskPlan` + current step), driven by `AutonomyEngine` progress events.

1. **Status line** — the glow caption shows the live step ("Orion researching…",
   "Step 4 of 5").
2. **Voice narration** — milestones only (plan up front, major transitions,
   result/failure) — JARVIS-concise, not every micro-step.
3. **Task panel** — a floating, accent-themed card that **auto-opens on task
   start**:
   - The goal + a **Stop** button.
   - The plan as a **live checklist**: each step shows its crew member + status
     (○ pending · ◐ running · ✓ done · ✗ failed); current step highlighted.
   - **Click a step to expand** its result/output.
   - Collapsible (status line + voice still convey progress).

## Section 5 — Reliability, edge cases & testing

**Second-wake fix (task #1):** after any conversation/turn ends, return to a
clean wake-listening state (`mode = .wake`, `isSuspended = false`, fresh
recognition); rolling restart keeps wake alive. Diagnose from the trace; lock
with a test before building the engine.

**Edge cases:** task failure → Verify → Recover (capped) → honest stop;
stuck/runaway → max steps + timeout + Stop; destructive → confirm; free-tier load
→ scheduler paces; one task at a time; bad plan → Stop/Verify catch it.

**Testing:**
- **Unit:** `TaskPlan`/`TaskStep`, planner-output parser (goal→steps),
  **`RequestScheduler`** (bucket selection + pacing with a mock clock — the key
  piece), intent router (chat vs task), local verifier (tool-result→pass/fail),
  destructive detection, sub-agent tool-scoping.
- **Manual smoke:** end-to-end tasks, panel, narration, Stop, free-tier pacing.
- Keep all v3 tests green + add these.

## Suggested implementation staging (for the plan)

1. **Second-wake fix** (diagnose + test + fix) — clean wake re-arm.
2. **`RequestScheduler`** (TDD: bucket selection + pacing with mock clock); route
   existing model calls through it.
3. **Models + intent routing** (`TaskPlan`/`TaskStep`, router) + planner.
4. **Named crew** (registry, personas, scoped tools, capped ReAct).
5. **`AutonomyEngine`** loop (execute + local verify + recover + destructive gate).
6. **Task panel + status + narration** wired to engine events.
7. Settings (crew list/toggles) + polish.

## Risks / call-outs

- **Agent capability isn't magic** — Verify/Recover catches failures and reports
  honestly; not every hard task will succeed.
- **Free-tier pacing** trades speed (never correctness) under heavy load.
- **Destructive side-effects** already executed can't be undone on Stop.
- Talk-over barge-in remains blocked (AEC); continuous follow-up is the model.
