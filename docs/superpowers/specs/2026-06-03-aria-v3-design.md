# Aria v3 — Fast, Conversational Aria — Design Spec

**Date:** 2026-06-03
**Status:** Approved (pending final spec review)
**Builds on:** Aria v2.0.0

## Summary

v3 turns Aria from a one-shot voice command tool into a **fast, continuous,
human-feeling conversation** — you say "Hey Aria" once and then talk back and
forth naturally, she **streams her reply** (starts talking in a few hundred ms),
and you can **interrupt her mid-sentence** (barge-in). Under the hood she gets
smarter and snappier via **native function-calling**, **model routing**, and an
**on-device audio pipeline with echo cancellation**. Ears and voice stay
on-device (private, cheap, reliable); only the streamed "brain" call (and an
optional screenshot) touches the cloud.

## Roadmap context (the JARVIS vision)

End goal: a personal JARVIS, eventually sold as a premium Mac app. Decomposed
into pillars, each its own spec → plan → build:
- **A — Responsiveness/speed** ⟶ *this spec (v3)*
- **B — Conversational feel** ⟶ *this spec (v3)*
- **C — Agentic power / computer use** ("do anything") ⟶ **v4**
- **D — Productization** (sign+notarize, .dmg/App Store, free vs Pro, managed
  key, payments, marketing) ⟶ later track

**v3 = A + B.** Speaker voice-ID is a **v3.1 fast-follow**. Computer-use, cross-
session memory/proactivity, and the Gemini Live API ("Pro ultra-realtime" mode)
are explicitly out of v3.

## Goals

- Continuous multi-turn conversation from a single wake.
- Streaming replies — she starts speaking almost immediately.
- Barge-in — interrupt her naturally; her voice stops, your new turn is captured.
- Faster + smarter: native function-calling, model routing, fewer round-trips.
- Stay on-device for audio (private, cheap → important for a sellable product).

## Non-Goals (deliberately out of v3, YAGNI)

- Speaker verification / "only my voice" → **v3.1**.
- Computer use / UI control (click/type/drive any app) → **v4 (pillar C)**.
- Cross-session long-term memory + proactivity → later.
- Productization (notarization, payments, managed key, .dmg/App Store) → **pillar D**.
- Gemini Live API realtime voice-to-voice → possible future **Pro** mode.

## Decisions (locked with user)

| Topic | Decision |
|-------|----------|
| Interaction model | Continuous conversation + streaming + barge-in |
| Architecture | Custom on-device streaming pipeline (not Gemini Live API) |
| Voice-ID | Fast-follow (v3.1), not in v3 core |
| Tools | Migrate to native Gemini function-calling |
| Streaming voice | On-device Apple voice = the instant default; Gemini cloud voice stays optional (slightly behind) |

---

## Section 1 — Architecture & components

**New:**
- **`ConversationSession`** — owns one continuous conversation: the
  `listen → respond → listen` loop, rolling dialogue context, and end conditions
  (silence timeout, dismiss phrase). Started by wake; ends back to idle wake.
- **`StreamingResponder`** — drives the streaming Gemini turn; splits incoming
  text into sentences on the fly and feeds them to the voice queue immediately.
- **`SentenceChunker`** — util: token stream → speakable sentence chunks.

**Changed:**
- **`WakeWordEngine` + `ConversationListener`** — wake detection stays; during a
  session a continuous listener segments turns (VAD) and enables barge-in. Audio
  input switches to macOS **voice-processing I/O (echo cancellation)**.
- **`GeminiClient`** — add `streamSend` (`streamGenerateContent` SSE) and
  **migrate tools to native function-calling** (replacing JSON-in-text), so the
  model can stream prose AND call tools in one turn.
- **`VoiceEngine`** — streaming/queued playback (sentence-by-sentence), instant
  stop on barge-in. Apple + Gemini voices both keep working.
- **`AgentOrchestrator`** — loop driver around function-calling + streaming; adds
  model routing and the skip-screenshot fast path.
- **`IslandView`** — caption streams in; states reflect continuous listen/speak.

Throughline: on-device for ears+voice (private, cheap, reliable), cloud only for
the streamed brain, native function-calling so speech and tools coexist.

## Section 2 — Conversation flow & state machine

1. **Wake-listening** (idle) — on-device "Hey Aria", aurora hidden.
2. **Wake → session starts** — aurora appears; first turn captured (incl. same-
   breath command).
3. **End-of-turn** — VAD endpoints on ~0.8 s trailing silence → finalize → send.
4. **Respond (streaming)** — *chat:* stream text → sentence chunks → speak,
   caption streams, fast model, screenshot skipped. *action:* short spoken
   preamble, model calls tools (function-calling), results feed back, final
   spoken result streams.
5. **She finishes → back to listening immediately** (no re-wake); session holds
   dialogue so follow-ups have context.
6. **Repeat** until an end condition.

**Barge-in:** mic stays open while she talks, fed through echo cancellation so it
only hears the user. Speech onset → stop TTS mid-sentence, cancel the in-flight
response, capture the new turn. *Caveat: a tool side-effect already in motion
can't always be undone.*

**End conditions:** silence timeout (~8–10 s) → end; dismiss phrase ("thanks
Aria"/"that's all") → end; menu-bar/hotkey toggle.

**Context scope:** session-scoped dialogue; resets on session end. (Cross-session
memory is a later pillar.)

## Section 3 — Streaming + tools (speech and tools coexist)

- **`streamSend`** uses `streamGenerateContent` (SSE), yielding **text deltas**
  and **function calls** as a live event stream.
- **Native function-calling:** each tool (system, apps, web_search/fetch, dynamic
  codegen, sub-agents) becomes a Gemini `functionDeclaration`. The model emits
  real `functionCall` parts with structured args; the app maps
  `functionCall → execute() → functionResponse` (reusing existing tool plumbing).
- **Unified turn loop:**
  ```
  user turn → streamSend →
     ├─ text delta   → SentenceChunker → speak chunk now
     ├─ functionCall → execute tool → functionResponse → model continues
     └─ done                          → turn complete
     (bounded by a max tool-round cap, like v2's loop)
  ```
  No JSON parsing, no separate chat/action router — the model talks and calls
  tools naturally.
- **Sentence chunking:** emit a chunk on each sentence boundary (`. ? !`/newline
  or length cap) so the first sentence speaks while the rest still streams.
- **Voice queue:** plays chunks in order, stops instantly on barge-in. The
  **on-device Apple voice is the instant default**; the Gemini cloud voice stays
  available but is inherently a bit behind (network per chunk).

## Section 4 — Barge-in & echo cancellation

- **Echo cancellation:** input switches to macOS voice-processing I/O
  (`AVAudioEngine` voice processing / `kAudioUnitSubType_VoiceProcessingIO`) →
  Apple AEC + noise suppression subtracts her own playback from the mic. Works
  for Apple TTS and the Gemini WAV (both play out the default output AEC uses as
  reference).
- **VAD:** RMS energy off the audio tap + onset debounce (~150–200 ms). Drives
  endpointing (~0.8 s trailing silence) and barge-in (onset while she speaks).
- **Barge-in mechanics:** stop TTS + clear queue → cancel the in-flight stream &
  pending tool rounds (best-effort) → capture the new turn (SFSpeech already
  transcribing).
- **False-fire guards:** ~300 ms arm-grace after she starts, min-speech-duration,
  energy floor; a **sensitivity slider** and **"barge-in off"** fallback (AEC
  varies by hardware; built-in mic+speakers are the sweet spot).
- **Continuity:** SFSpeech runs continuously through the session, reusing v1.0's
  cascade fix + rolling restart so recognition never silently dies.

## Section 5 — Speed & intelligence

**Faster:**
- **Model routing per turn:** default fast (`gemini-2.5-flash`/`flash-lite`);
  escalate to `gemini-2.5-pro` only for complex/agentic turns (heuristics + the
  model can flag "needs deeper reasoning").
- **Skip the screenshot for chit-chat;** capture only when the turn needs to see.
- **Parallel tools:** run independent function calls concurrently (task group).
- **Stay warm:** pre-warm audio engine + SFSpeech; reuse a keep-alive HTTP/2
  connection.
- **Context caching + trimming:** Gemini context caching for the static system
  prompt + tool schema; cap dialogue history to recent turns.
- **Latency target:** she starts speaking ~1–1.5 s after you stop (the ~0.8 s
  end-of-turn silence dominates; tunable). Streaming + on-device voice keep the
  first word fast even on long answers.

**Smarter:**
- Native function-calling ⇒ far fewer "dumb" tool failures than JSON-in-text.
- Stronger model on hard turns, woven into a **plan → act → verify** loop.
- Conversational context for coherent follow-ups; graceful failure ("I can't do
  that yet") from v2 — never silent.
- Tight persona-driven prompt: confident, concise, asks a clarifying question
  when genuinely unsure instead of guessing.

## Section 6 — Reliability, edge cases, testing

**Reliability / edge cases:**
- Flaky key (404/503): streaming client reuses v2 retry-with-backoff + model
  fallback; stream dies mid-reply → brief graceful recovery, session continues.
- Barge-in false-fires: grace + min-duration + energy floor + sensitivity slider
  + "barge-in off".
- Network drop mid-stream: detected → short "lost you for a sec," turn retries.
- Tool errors / destructive actions: function-call errors feed back so she
  recovers/reports; destructive tools keep v2's confirmation gate.
- Runaway protection: max tool-rounds per turn + turn timeout; silence timeout
  ends the session.
- Wake never dies: reuse v1.0 cascade fix + rolling restart.
- Privacy: ears + voice on-device; only text (+ optional screenshot) to cloud.

**Testing:**
- **Unit:** `SentenceChunker`, model router, VAD/endpointing decision logic,
  SSE→event parser, function-call→execute mapping, backoff/fallback (extend v2).
  Keep all 64 existing tests green + add these.
- **Manual smoke (real audio can't be unit-tested):** end-to-end conversation,
  barge-in, latency feel, AEC across mic/speaker setups.

## Suggested implementation staging (for the plan)

1. Streaming text path (`GeminiClient.streamSend` + `SentenceChunker` + streaming
   voice queue) behind the existing one-shot flow — prove streaming speech.
2. Native function-calling migration + streaming agentic loop (replace JSON-in-
   text), keep tests green.
3. `ConversationSession` continuous loop (multi-turn, end conditions).
4. Echo cancellation (voice-processing I/O) + VAD + barge-in.
5. Model routing + skip-screenshot + parallel tools + context caching.
6. Settings (barge-in sensitivity/toggle, silence timeout), persona prompt
   tuning, polish.

## Risks / call-outs

- **AEC hardware variance** — barge-in quality depends on mic/speaker setup;
  mitigated by sensitivity + disable fallback.
- **Streaming + function-calling is a real rewrite** of the model-interaction
  core — staged so each step stays build+test green and shippable.
- **Latency floor** is the end-of-turn silence; adaptive endpointing can come
  later if ~0.8 s feels slow.
- The flaky `AQ.` key still rides every turn — resilience carried from v2, but a
  hard-throttled key remains a ceiling (a plain `AIza` key is steadier).
