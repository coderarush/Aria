# Aria v11.1.1 — "The Operator" Spec

> Status: DRAFT for review. v11.0.1 (the small polish release) is the predecessor;
> this is the **huge** release. Author: working session 2026-06-13.

## North star

Aria stops being a thing you *summon* and becomes a presence that *operates your
computer with you* — it understands what's on screen, acts across every app to
finish real multi-step jobs, and gets measurably smarter every week. The bar:
the first assistant a power user trusts to **do the work**, not just talk about it.

Beating Siri is table stakes. The target is to beat every Mac AI tool (Hey Clicky,
Wispr Flow, Raycast AI) by being the one that *completes outcomes*.

## The one-line bet

**Reliable, trustable computer-use.** Everything else (connectors, memory,
personalization, voice) is in service of Aria finishing a job in any app and the
user *believing it did it right*. Trust is the product, and trust = transparency +
reversibility + reliability.

---

## Pillars

### 1. The Operator — reliable multi-app computer-use (flagship)

What exists today: `AutonomyEngine` (plan→execute→verify→recover, resumable,
journaled), `ComputerUse/` (AXReader, UIActuator, VisionLocator, ScreenContext,
AXGeometry), `Safety` gates, `UndoStack`, `ActivityLog`. The bones are here. v11.1.1
hardens them into something you'd actually hand a real task.

- **Action receipts.** Every action Aria takes produces a receipt: what it did,
  where (app/window/element), the before/after, and a one-click **undo**. Surfaced
  live in the task panel and persisted to the activity log. This is the trust core.
- **Universal undo.** Extend `UndoStack` to cover computer-use actions (typed text,
  clicks that changed state, file ops, sends). Where true undo is impossible
  (an email sent), Aria must *say so before acting* and gate behind approval.
- **Robust targeting.** Today's AX + vision fallback gets flaky on non-standard UIs.
  Add: element re-resolution on retry, visual grounding confidence scores, and a
  "show me what you're about to click" preview for risky steps.
- **Verification that's real.** After each step, verify the expected post-condition
  (the field now contains X, the row was added) before continuing — not just "the
  click didn't throw." Recover or ask when a step's effect can't be confirmed.
- **Dry-run / preview mode.** For a multi-step plan, optionally show the whole plan
  with predicted effects and let the user approve once, then watch it run with
  receipts.

**Success metric:** a suite of ~20 real tasks ("add these 5 expenses to the sheet",
"unsubscribe from these newsletters", "rename and file these downloads") completes
end-to-end ≥90% unattended, with every action reversible or pre-approved.

### 2. Connectors as a first-class action surface

v11.0.1 lands OAuth + Gmail/Calendar read tools. v11.1.1 makes connectors a
read+write action layer Aria works through:

- Gmail: triage, draft, send (gated), archive, label.
- Calendar: create/move/cancel events, find-time across attendees.
- Drive/Notion/Slack: read context, post/update, summarize a channel.
- A uniform connector-tool contract so adding a provider is declarative.
- The credential reality (user supplies a client ID per provider) stays; v11.1.1
  adds an optional hosted-relay so non-technical users can connect without a
  Google Cloud project. **(Open question — see below.)**

### 3. Memory that compounds into a model of *you*

Pieces exist (conversation, knowledge, personal context, work journal, unified
recall). v11.1.1 turns them into a living model of the user:

- **Entity graph.** Who's Sara, what's "the Q3 deck", which project is "the launch".
  Resolve references across all stores. Built incrementally from observed work.
- **Style capture.** Learn the user's writing voice so drafted email/Slack/messages
  sound like them, not a bot. On-device, from their own sent text.
- **Recall that ranks by *you*, not just lexical match** — recency, frequency,
  and the entity graph weight what surfaces.

### 4. Ambient anticipation that acts (carefully)

v11.0.1 ships precision-gated nudges. v11.1.1 lets the highest-confidence,
fully-reversible ones *act* with a glanceable "I did X — undo?" receipt
(e.g. pre-drafting a reply, filing a download), strictly inside the daily budget
and the approval rules. Anticipation that does, not just suggests — without
becoming creepy or noisy. Consent + visibility are non-negotiable.

### 5. Continuity — iPhone companion

The Mirror bridge exists. v11.1.1 adds a phone presence: handoff ("continue on
Mac"), actionable notifications (approve/undo from the phone), and remote
triggering. This is the category-defining, very-un-Siri move. **(Scope: likely a
v11.1.x follow-on if it balloons — see open questions.)**

### 6. Voice that disappears

Sub-300ms first token (local instruct + fast cloud, both now wired), fully
interruptible, and warmer/emotional TTS so the conversation stops feeling like a
tool. Mostly tuning + the local-first work already started; the win is latency.

---

## Architecture approach (incremental, preserve-first)

Per the project constitution: **Preserve → Improve → Expand.** No rewrites.

- **Receipts/undo**: extend `UndoStack` + `ActivityLog` with a `Reversible`
  protocol each computer-use/connector action conforms to (`do()` / `undo()` /
  `describe()`). The Operator only runs actions that are either reversible or
  explicitly approved.
- **Targeting/verification**: enhancements live inside `ComputerUse/` + the
  `AutonomyEngine` verify step; add a `PostCondition` to each `TaskStep`.
- **Connectors**: a `ConnectorAction` tool contract over the existing
  `ConnectorStore`; providers declare their read/write capabilities.
- **Entity graph + style**: new `Core/Identity/` (on-device, opt-in), feeding
  `UnifiedRecall` ranking and the draft tools.
- **Continuity**: extend `Mirror/MirrorBridge`.

Everything additive; every new capability behind a setting; cloud byte-identical
when opted out.

## Phasing (so it ships in slices, not a big bang)

- **Phase A — Trust:** receipts + universal undo + real verification + dry-run.
  (Ship-able alone; makes today's autonomy trustworthy.)
- **Phase B — Reach:** connector write-actions (Gmail/Calendar first).
- **Phase C — Knowing you:** entity graph + style capture → personalized drafts.
- **Phase D — Anticipation that acts** (gated on A's receipts being solid).
- **Phase E — Continuity** (iPhone) — may slip to v11.1.x.
- **Phase F — Voice latency/warmth** (parallelizable throughout).

## Success metrics (the whole release)

1. Operator task suite ≥90% unattended completion, 100% of actions
   reversible-or-pre-approved.
2. Median voice first-token <300ms (local) / <500ms (cloud).
3. A connected user can complete an inbox-triage + calendar-schedule flow by voice.
4. Drafts pass a blind "did the user write this?" test ≥60% of the time.
5. Zero silent irreversible actions — every send/delete/pay is gated and logged.

## Risks

- **Computer-use reliability** is the hard problem; non-standard UIs break AX +
  vision. Mitigation: confidence scoring + ask-when-unsure + receipts so failures
  are visible and recoverable, never silent.
- **Trust/safety:** an assistant that acts can do damage. Mitigation: reversibility
  invariant, approval gates on irreversible actions, full receipts, daily budgets.
- **Scope:** this is large. Phasing (A→F) lets Phase A ship and deliver value alone.
- **The frozen voice stack** stays frozen except the latency tuning, which is
  additive (provider/model selection, already in motion).

## Open questions for the user (decide before building)

1. **Hosted OAuth relay?** Building one lets non-technical users connect Gmail
   without a Google Cloud project, but it means running infrastructure and holding
   a relationship to their tokens. Ship connectors "bring-your-own-client-ID" only,
   or invest in a relay? (Affects Pillar 2 + business model.)
2. **How autonomous should "anticipation that acts" be?** Draft-only-then-approve,
   or let fully-reversible actions execute with an undo receipt? (Trust vs. magic.)
3. **iPhone companion in 11.1.1 or 11.1.x?** It's a big lift; including it widens
   scope a lot.
4. **Privacy posture for style/entity learning** — fully on-device only (slower,
   private) or allow opt-in cloud for better personalization?
5. **What's the launch-defining demo?** Pick the one task that, done flawlessly on
   stage, sells the release — it should anchor the Operator task suite.

## Recommended first move

Build **Phase A (Trust: receipts + universal undo + real verification)** first.
It's self-contained, it ships value alone, and it's the prerequisite that makes
every other "Aria acts" capability safe. Everything else compounds on it.
