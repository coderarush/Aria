# Aria v6 — Generic Computer Use ("do anything on the Mac") — Design Proposal

**Date:** 2026-06-04
**Status:** Proposal (for review — not yet approved)
**Builds on:** Aria v5 (autonomy + reliability + free-forever fallback)

## Summary

v6 is the headline leap: Aria can operate **any** Mac app — **see the screen, click,
type, read** — not just run shell/AppleScript. This turns "do anything" from a
slogan into reality: fill a form, edit a video, click through an app with no
scripting interface, drive a website. It plugs into the v4 autonomy loop as a new
set of tools, so a goal like *"open Figma and export the first frame as PNG"* becomes
a real plan that clicks the actual buttons.

**This is the demo that goes viral** — a JARVIS visibly operating your Mac.

## The core problem & the answer

To operate any app you must **perceive** (what's on screen + where) and **act**
(move/click/type). Two mechanisms, used as a hybrid:

1. **Accessibility API (AX) — primary.** Every native/standard macOS app exposes a
   tree of UI elements (`AXUIElement`): buttons, fields, their labels, roles,
   values, and screen positions. Reading it is **deterministic, instant, free** (no
   model tokens), and acting via `AXPress`/`AXSetValue` is precise. This covers the
   large majority of apps.
2. **Vision — fallback.** For apps AX can't read (Electron, canvas, games, custom-
   drawn UIs), screenshot the screen → a multimodal model returns the element's
   coordinates → click via `CGEvent`. Slower, costs vision tokens (so it's the
   fallback, keeping it cheap and free-tier-friendly), works on *anything*.

**AX-first, vision-fallback** = fast + free for most actions, universal coverage for
the rest.

## Architecture & components

**New (Core/ComputerUse/):**
- **`AXReader`** — reads the frontmost app's accessibility tree into a flat list of
  actionable elements: `{role, label, value, frame, path}`. Filters to the useful
  (buttons, fields, menus, links, checkboxes).
- **`UIActuator`** — performs actions: `press(element)`, `setValue(element, text)`,
  and low-level `click(point)` / `type(text)` / `key(combo)` via `CGEvent` for the
  vision path or where AX actions aren't available.
- **`VisionLocator`** — screenshot → multimodal model ("return the bounding box of
  the element matching this description") → screen coordinates. Used only when AX
  can't find the target.
- **`ScreenGrounding`** — converts AX frames / vision boxes to global screen points
  for CGEvent, handling Retina scaling + multi-display.

**New tools (registered like v4's tools, usable by the autonomy engine + crew):**
- `ui_read` — return the actionable elements of the frontmost app (so the model
  knows what it can click).
- `ui_click` — click an element by label/role (AX) or by description (vision
  fallback).
- `ui_type` — type text (into the focused field, or after clicking a field).
- `ui_key` — press a key combo (⌘S, ⏎, ⌘C…).
- `ui_find` — locate an element + report whether it exists / its state.

**Changed:**
- **`AutonomyEngine` / crew** — a new crew member, e.g. **Pilot** 🕹 (operates app
  UIs), scoped to the `ui_*` tools. The planner uses `ui_read` to perceive, then
  `ui_click`/`ui_type` to act, verifying with another `ui_read`.
- **Permissions** — needs **Accessibility** (`AXIsProcessTrusted`) + **Screen
  Recording** (already have, for vision). Onboarding must prompt + guide to System
  Settings → Privacy & Security → Accessibility.

## The loop (perceive → act → verify)

1. Plan step: *"click the Export button in Figma."*
2. `ui_read` → AX tree → find an element with role=button, label≈"Export".
3. Found → `ui_click` (AXPress). Not found in AX → `VisionLocator` (screenshot →
   model → coords) → `ui_click(point)`.
4. Verify: `ui_read` again / screenshot to confirm the UI changed as expected;
   else recover (the v5 never-dead-end logic applies).

## Safety (critical — this is powerful)

- **Visible indicator** — a clear "Aria is controlling your Mac" overlay while
  `ui_*` actions run; the user can see and Stop instantly.
- **Confirm destructive UI** — clicking "Delete", "Send", "Buy", "Pay" → the v4
  Safety gate confirms first (extended to UI labels).
- **Bounded** — max actions per task + timeout (a runaway clicker is dangerous).
- **No background hijack** — only acts on the user's request; never autonomously.

## Free-tier fit

- **AX path = $0** (no model). Most clicks/reads cost nothing.
- **Vision path** uses the multimodal model — routed through the v5.5 provider chain
  (Gemini vision; Groq/others are text-only, so vision stays on Gemini or a vision-
  capable provider). AX-first minimizes vision calls → stays free-tier-friendly.

## Testing

- **Unit:** AX-element filtering/mapping (pure, against a fixture tree),
  ScreenGrounding coordinate math (Retina/multi-display), VisionLocator box→point,
  destructive-UI detection, the `ui_*` tool input parsing.
- **Manual:** drive TextEdit / Notes / Safari / a known app end-to-end; the visible
  indicator + Stop; permission-denied path.
- Keep all v5 tests green.

## Suggested staging (for the implementation plan)

1. **Permissions + `AXReader`** — request Accessibility, read + filter the frontmost
   app's element tree (TDD the mapping).
2. **`UIActuator`** — AX press/setValue + CGEvent click/type/key; `ScreenGrounding`.
3. **`ui_*` tools** — register; wire into the autonomy engine; add the **Pilot** crew
   member.
4. **`VisionLocator`** — screenshot → model → coords fallback when AX misses.
5. **Safety + indicator** — visible "controlling" overlay, Stop, destructive-UI
   confirm, bounds.
6. **Polish + demos** — tune on real apps; record the marketing clips.

## Risks / call-outs

- **Accessibility permission friction** — users must grant it manually; onboarding
  must make this painless. Without it, v6 can't act.
- **Vision accuracy** — coordinate precision from a model is imperfect; AX-first
  avoids relying on it. Verify-after-act catches misclicks.
- **It's powerful = it's dangerous** — the safety floor (indicator, confirm, bounds,
  Stop) is non-negotiable before shipping.
- **App variance** — Electron/custom apps lean on the vision path (slower, costs
  tokens). Coverage is "most apps fast + free, the rest slower."
- **This is the v5→v6 reach** — significant. Worth a dedicated spec review + a spike
  on AX reading a couple of real apps before committing the full plan.

## Beyond v6 (roadmap tail)

- **v7 — Productization**: notarized `.dmg`, free vs Pro tiers, managed-key option,
  Gumroad/Lemon Squeezy licensing, landing page, a final name (Aria has SEO/TM
  conflicts — rename at launch).
- Ongoing: local TTS (free voice), more first-class integrations, deeper memory.
