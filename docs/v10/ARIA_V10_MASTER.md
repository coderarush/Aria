# ARIA V10 PRE-RELEASE — FINAL PRE-LAUNCH RELEASE

(Verbatim directive from the user, 2026-06-10. Governing docs ARIA_V9_MASTER.md and
ARIA_WEBSITE_V9.md remain in force — see docs/v9/.)

North star: "The fastest way to get work done on a Mac."
Quality bar: Apple, Raycast, Arc, Linear. Calm, capable, trustworthy, fast, premium.
Philosophy: Preserve → Improve → Expand. No feature removal. Regression validation always.
Launch test for every decision: does it make Aria more premium, useful, faster, or more reliable?

P1  Premium macOS experience — Spotlight-quality overlay, native transitions/notifications,
    refined blob, faster perceived latency, improved menu bar.
P2  Workflow planning engine — understand → plan → present when appropriate → execute →
    verify → report ("Prepare me for tomorrow").
P3  Daily briefing system — first-class, signature workflow (calendar/tasks/notes/recent work).
P4  Project memory — "What were we working on yesterday?" / "Continue my Aria work."
P5  Agentic workflows — multi-step, chained, background, retry, progress, verification.
P6  Integrations as modular skills — Calendar, Mail, Browser, Finder, Notes first.
P7  Customization — theme, voice, wake phrase, shortcuts, workflows, notifications, behavior.
P8  Transparency — workflow history, context inspector, active task view, model usage.
P9  Performance — startup, latency, animation, memory, CPU. Performance is a feature.
P10 Reliability — bug-hunt before features; comprehensive regression before shipping.

## ARIA_DEMO_MODE — launch preparation plan (Phase A decision, 2026-06-10)

Demo mode graduates from a marketing aid to launch infrastructure:
1. **Smoke backbone (DONE):** `make smoke` drives the real app headlessly in
   ARIA_DEMO_MODE — deterministic, zero network/quota — asserting startup,
   wake, capture, two full conversation turns, and re-arm. Gate every phase
   and the launch build on 10/10.
2. **Recording rig (Phase D):** scripted demo scenarios via ARIA_DEMO_SCRIPT
   for the website/video captures (meeting prep, Downloads organize,
   knowledge query) — one take, every take.
3. **Press/tester mode (Phase D):** document `ARIA_DEMO_MODE=1` in the README
   so reviewers can exercise the full product without keys.
