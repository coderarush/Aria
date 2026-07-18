# Live Loop — Live Smoke Checklist

**Date:** 2026-07-10. **Branch:** `runtime-os` (tip includes the 07-10 safety
hardening: unattended runs fail closed, autonomous mode defaults OFF).
**Why this exists:** the Live Loop shipped 07-02 with the full unit suite green,
but the spec's live-smoke section (real calendar/mail/screen triggers on the
installed signed app) has never been run. Shipped code ≠ working JARVIS until
this passes.

## Setup (once)

- [ ] Install the fresh build: open `.build/Aria.dmg` (built 2026-07-10 at tip),
      drag Aria to /Applications, launch **from /Applications** — EventKit, AX,
      and Automation permissions only stick on the installed signed app, not
      `make run`.
- [ ] Grant on first prompt: Calendars, Reminders, Accessibility, Screen
      Recording, Microphone, Automation.
- [ ] Confirm loop is on: `liveloop.enabled` defaults true; master kill switch
      is `app.disableLiveLoop` (must be false/absent). Idle tick = 45s
      (`liveloop.tickSeconds`); evaluations also fire on signal events.
- [ ] Note: `pauseInLowPower` defaults true — take the Mac off Low Power Mode
      or the loop won't tick.

## Scenario 1 — MeetingPrep (`meeting_prep`, tier `auto`)

- [ ] Create a real calendar event starting ~14 minutes out, with a title that
      matches a recent mail thread.
- [ ] Within a tick or two: blob signals, Aria runs prep **without asking**
      (auto tier), delivers a short spoken brief citing the thread/attendees.
- [ ] Card reports what was done; entry lands in the activity log.

## Scenario 2 — InboxTriage (`inbox_triage`, tier `confirm`)

- [ ] Send yourself an email that reads important (deadline, question).
- [ ] Aria offers ("New mail just landed — want me to triage…") and **pauses at
      the card** — no action before approve.
- [ ] Approve → summary + drafted reply in your style. Draft is created,
      **never sent** — verify it sits in Drafts.
- [ ] Dismiss path: send another, dismiss the card, verify nothing ran.

## Scenario 3 — ScreenCoPilot (`screen_copilot`, tier `confirm`)

- [ ] Bounce repeatedly between two apps doing the same manual step
      (e.g. copy from Numbers → paste into Mail, 4-5 rounds).
- [ ] Aria notices ("You've bounced between X and Y…"), offers help, waits for
      approval before touching anything.
- [ ] Approve → walkthrough or does the next round. Conservative trigger —
      false-fire on normal app switching = fail.

## Scenario 4 — DailyBrief (`daily_brief`, tier `auto`)

- [ ] First unlock of the morning (or simulate: quit Aria, relaunch in the
      morning window): spoken brief covering calendar, unread mail, reminders,
      yesterday's work — unprompted.
- [ ] Brief fires **once**; no repeat on later unlocks the same day.

## Cross-cutting gates

- [ ] Confirm tier never acts before approve; auto tier never asks.
- [ ] **Unattended fail-closed (new 07-10):** with autonomous mode ON, a
      background/silent run must still decline important-irreversible actions
      and refuse generated-code execution.
- [ ] Only one live proactive card at a time; stale cards expire (TTL).
- [ ] Snooze honored; "never" kills that recognizer permanently.
- [ ] Global pause (`liveloop.enabled` off in Settings) silences everything
      immediately.
- [ ] Every fired playbook is in the activity log with outcome.
- [ ] Idle cost sane: with loop on and nothing happening, Aria near-0% CPU
      between ticks.

## Recording results

Mark each box pass/fail with a one-liner. Failures become fix-tasks on
`runtime-os`; a full pass makes the Live Loop *validated*, unblocking the
launch track (notarize / testers / film).
