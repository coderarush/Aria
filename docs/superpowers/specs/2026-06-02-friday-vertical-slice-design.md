# Friday — Vertical Slice (v0) Design

Date: 2026-06-02
Status: Approved (slice scope)

## Vision (full project)

Friday: native Swift/SwiftUI macOS AI **agent** that takes actions — wake word,
floating orb, screen vision, Gemini brain, ~30 tools, dynamic tool generation,
sub-agents, behavioral learning, smart-mirror bridge. Open source, MIT.

The full spec is large (≈10 independent subsystems). It will be built in staged
passes, each compiling and tested before the next. This document covers **only
the first slice**.

## Slice goal

One full loop, end to end, that **builds and runs** on macOS 13+:

```
"Hey Friday" → orb materializes → listen (waveform) → capture screen
            → Gemini (screenshot + transcript + history) → response card
            → auto-dismiss after 8s / tap / "dismiss"
```

No tools, sub-agents, or learning yet. This proves the spine and the seams.

## Build system

SwiftPM package + `Makefile` that assembles `Friday.app` (Info.plist with
`LSUIElement`, mic/screen usage strings). Verifiable from CLI via `swift build`.
An XcodeGen `project.yml` generates `Friday.xcodeproj` for Xcode users. Same
sources both ways.

Rationale: hand-written `.pbxproj` is fragile and hard to verify from terminal;
SwiftPM is reproducible and CLI-verifiable. The real deliverable ("builds and
runs on macOS 13+") is met.

## Components (slice)

- **FridayApp / AppDelegate** — `@main`, `LSUIElement=true`, menu bar ⬡ status item.
- **WakeWordEngine** — `SFSpeechRecognizer` + `AVAudioEngine`, on-device, rolling
  3s buffer, accepts mishearings ("Freddy/Frieda/Friday"), fires `onWake`.
- **ScreenCaptureEngine** — `ScreenCaptureKit`, primary display, JPEG 75% / max
  1920px, last-3 in memory, never written to disk.
- **GeminiClient** — async/await, retry + exponential backoff on 429, 30s identical
  request cache, structured JSON contract.
- **AgentOrchestrator** — transcript → Gemini → response; parses `answer/clarify`
  now, `action/multi_action` routed to a "not yet implemented" stub (protocol real
  from day 1).
- **ConversationMemory** — JSON persistence in App Support, last-50 on disk,
  last-6 sent to Gemini.
- **OrbViewModel** — state machine: `.hidden → .listening → .thinking → .responding
  → .hidden`, `.error` transient.
- **OrbView / ResponseCard / WaveformView** — SwiftUI, animated gradient/blur glow
  (Metal deferred), frosted glass card with markdown, mic-level ring. Orb hosted in
  a borderless floating non-activating `NSPanel`, draggable, all-spaces.
- **Utilities** — KeychainManager (API key), PermissionsManager (mic/screen),
  Logger (`os.Logger`).

## Gemini contract

Request per turn: screenshot (b64 JPEG) + transcript + last-6 history + system
context (app, time, user). Response:

```json
{ "type":"answer|action|multi_action|clarify",
  "message":"...", "confidence":0.0,
  "actions":[], "followup":null }
```

## API key

Migrate from `~/Friday/.apikey` → Keychain on first run if Keychain empty.

## Deferred (NOT in slice)

All Tools, DynamicToolFactory, SubAgents, PatternEngine/behavioral learning,
MirrorBridge, full Settings, Onboarding, Metal shaders. Architecture leaves
protocol seams + stubs so they bolt on without rework.

## Quality bar (slice)

No force-unwraps in production paths; async/await throughout; unit tests for
GeminiClient (mocked URLProtocol), ConversationMemory, KeychainManager.
