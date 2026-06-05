# Aria v8 — "Alive" (organic, bubbly presence) — Design Proposal

**Date:** 2026-06-04
**Status:** Built — staging 1–3 done; only on-device tuning (4) remains (needs the user).
**Builds on:** Aria v7

## Delivered

- **Alive presence:** bubble body, springy state pops, bouncier caption, face orb
  (toned: 54pt, soft glow), speaking breath envelope, **thinking swirl** (orbital ring).
- **Settings crash fixed:** NavigationSplitView → plain sidebar HStack+List (root-caused
  from crash report: re-entrant NSSplitViewController layout → executor-check SIGSEGV).
- **Beat-Clicky capability** (Aria *acts*, not just guides; free + private):
  - *Ambient screen awareness* — focused window/field + selected text fed each turn, so
    "summarize this / reply to her / translate the selection" just work (no screenshot).
  - *Spoken play-by-play* — short present-tense narration as each step runs (toggle).
  - *Type-target verify + self-heal* — ui_type fails honestly when no field is focused
    instead of typing into the void; the model clicks first and the engine retries.

Remaining: on-device tuning of motion/timing + battery check, and (optional) swapping the
synthetic speaking envelope for real TTS playback-amplitude metering.

## Vision (from the user)

Make Aria *look and feel alive — bubbly almost.* Right now her on-screen presence
(the edge glow + caption) is smooth but static. v8 gives her an **organic, living
body**: soft blobs that float, breathe, and react to your voice; springy, playful
state changes; a presence that feels like a creature listening, not a UI element.

## Principles

- **Organic over geometric** — morphing blobs, liquid motion, no hard rings.
- **Reactive** — swells and bubbles with the voice (audio level), pulses while
  thinking, settles when idle.
- **Springy, not linear** — every state change has spring physics (a little bounce),
  so it feels alive, not mechanical.
- **Restrained** — alive, not distracting; it's ambient, click-through, and calm
  between turns.

## Pieces

1. **Bubble layer** *(first — this commit)* — a `TimelineView` + `Canvas` of soft,
   blurred, multi-color blobs that drift, breathe (sin phases), and scale with
   `audioLevel`. Layered with the existing edge glow. The "bubbly" body.
2. **Springy state transitions** — listening/thinking/responding each enter with a
   spring (scale/opacity pop); idle settles.
3. **Voice-reactive core** — a central soft orb (like the website's) that breathes
   and ripples with speech.
4. **Thinking shimmer** — bubbles swirl/orbit while she's working.
5. **Caption** — keep, but let it rise with a softer, bouncier spring.

## Non-goals

- No heavy 3D/Metal (keep it light + battery-friendly; Canvas + SwiftUI animation).
- Don't change behavior/logic — purely the felt presence.

## Staging

1. Bubble layer (Canvas, audio-reactive, breathing) + wire into IslandView.
2. Springy state-transition animations.
3. Voice-reactive central orb + thinking swirl.
4. Tune on-device (calm idle, lively listening) + battery check.
