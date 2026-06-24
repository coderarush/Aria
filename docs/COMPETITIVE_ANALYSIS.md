# Aria vs. the field — HeyClicky & Siri (June 2026)

Research synthesis driving the Lens + local-first work on `runtime-os`. Goal:
Aria is the best screen-aware Mac agent in the world. This documents what the two
reference points actually do, where Aria already wins, and the gaps we closed.

## HeyClicky (heyclicky.com, by Farza)

What it is: a Mac-native, voice-first, screen-aware assistant that sits by your
cursor. Open-source, ~95% Swift, menu-bar process, Apple Silicon + Intel.

Capabilities (from their site + coverage):
- **Voice ask + spoken walkthrough.** Hold Control+Option, ask aloud, it answers —
  and can point an animated cursor at the exact button (tutor-beside-you) for apps
  like DaVinci Resolve, Figma, After Effects.
- **Screen awareness** — "sees everything you see."
- **Background agents** — say "clicky agent" to research, organize Notes/Calendar,
  or build a working Mac app.
- Windows version waitlisted. Local-vs-cloud and model not disclosed; privacy
  policy referenced but not detailed.

Notably **absent** from their public material: any circle/lasso-to-explain, any
draw-on-screen annotation, any stated on-device/private guarantee.

### Where Aria already matched or beat it
| Capability | HeyClicky | Aria |
|---|---|---|
| Voice, wake word, barge-in | yes | yes — Speex AEC, speaker verify, streaming |
| Screen awareness | yes | yes — ScreenCaptureKit (in-memory only), OCR, vision locate |
| Point at the right control | animated cursor | OperatorTargeting (confidence-gated AX + vision click) |
| Background agents | "clicky agent" | AgentCoordinator/SubAgent + Safety gates + receipts |
| Build/operate apps | yes | yes — computer use + tools, undo + activity log |
| Open source / Swift / menu bar | yes | yes |
| **Private / on-device** | not stated | **local-first by default** |

### The gap we closed (the differentiator)
HeyClicky has no "circle a thing and ask." We shipped **Lens** (`UI/Lens/`):
press ⌥⇧C, draw a loop around anything, Aria captures *just that region* and
explains it through the blob + voice. Plus a **draw-on-screen** annotation mode.
Rendered in Aria's gooey idiom — the stroke trails small morphing blobs (her
body), so it feels like Aria reaching onto your screen, not a marquee. This is a
capability HeyClicky's own marketing doesn't claim, executed on-brand.

## Siri AI (Apple, WWDC 2026)

What shipped: Siri rebuilt on Apple Foundation Models + **Google Gemini** via
Private Cloud Compute. **Visual Intelligence** (point the iPhone camera at
objects/text/scenes for contextual answers/actions). System orchestrator taps the
Spotlight index + App Toolbox on device. Writing assist, image gen, contextual
suggestions across apps.

Limits: most-advanced on-device model needs 12 GB RAM (iPhone Air / 17 Pro /
17 Pro Max only). Not at launch in the EU or China (regulatory).

### Where Aria wins
- **Whole-desktop vision, not a camera.** Visual Intelligence reads what the
  rear camera sees; Aria's Lens reads anything already on your Mac screen — an
  error log, a chart, a PDF, a UI control — and can act on it.
- **Truly local option.** Siri's "private" path still round-trips Gemini through
  Private Cloud Compute. Aria runs the model on *your* machine: local-first text
  routing (Ollama/Qwen) and now local-first **vision** (`VisionRouter` →
  `OllamaProvider.generateTextWithImage`, llava/qwen-vl). Only voice need ever
  leave, and only if you opt in.
- **Acts across every app**, not just Apple's App Intents surface — AX +
  computer-use vision fallback drives real UIs.
- **Open, inspectable, no hardware gate, no region lockout, free.**
- **Execution-first**: Objective → Understand → Plan → Execute → Verify → Report,
  with receipts + undo. Siri is still primarily request/response.

## What we built (runtime-os)
1. **Lens** — circle-to-explain (⌥⇧C / menu / "let me circle something") + draw-on-
   screen. Region-only capture (fraction-based, scaling-proof); **OCR-first**
   (on-device Vision.framework → local text model), vision fallback for images.
2. **Lens-to-action** — after circling, "translate that" / "fix this error" folds
   the circled content into the next command so the agent acts on it (`LensFollowUp`,
   whole-word deictic match, 120s freshness, consumed once).
3. **She points & teaches** — `show_me` pools a guidance blob onto a located element;
   **guided walkthroughs** ("walk me through exporting a PDF") point at each step in
   turn with spoken instructions (whole-desktop, local-first). Beats Clicky's tutor.
4. **Worker swarm** — agentic plans spawn one worker blob per step (visible sub-
   agents), dissolving as steps finish.
5. **Thinking constellation** — the HUD blob splits into orbiting small blobs and
   squishes back together (spring-driven).
6. **Local-first vision** — was Gemini-only; now routes on-device first
   (`VisionRouter`, `OllamaProvider.generateTextWithImage`), cloud fallback. Applied
   to Lens, `show_me`, walkthroughs, and computer-use targeting (`VisionLocator`).
7. **Hardening** — screen capture excludes Aria's OWN windows (she never sees her own
   overlays); `ConnectorStore` client-ID resolution injectable (fixed 2 env-fragile
   tests). Site got an Apple-grade motion pass + interactive Lens demo. Suite 1433
   green; release build concurrency-clean.

## Still open (honest)
- All Lens/stage/walkthrough/thinking GUI is **unrun headless** — feel, marker
  alignment, drag fidelity, and pacing need on-device validation.
- Multi-monitor: capture + overlays assume the primary display.
- Local vision model still manual-install (`app.localVisionModel` Settings field
  exists; no one-click pull yet).
- Walkthrough advances on a length-scaled timer; a "say next to advance" mode would
  be better.
