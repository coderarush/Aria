# Aria v8 — "Alive" (organic, bubbly presence) — Design Proposal

**Date:** 2026-06-04
**Status:** In progress
**Builds on:** Aria v7

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
