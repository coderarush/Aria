# Aria — V9 Pre-Release Working Context

**Status:** V9 pre-release on branch `aria-v9` (v8 shipped, merged to main).
**Governing docs (read these for product direction):**
- `docs/v9/ARIA_V9_MASTER.md` — product + engineering constitution
- `docs/v9/ARIA_WEBSITE_V9.md` — website design/motion/marketing constitution
- `docs/v9/ROADMAP.md` — Phase A–D implementation roadmap (A = stabilize, B =
  provider abstraction + local-first, C = knowledge engine/background agents/
  interaction/transparency, D = demo mode + website/launch)

## What Aria is
Execution-first intelligence layer for macOS. Turns user *intent* into *completed work*.
NOT a chatbot, NOT a Siri clone, NOT an LLM wrapper. The model is not the product —
the execution, workflow, context, and memory engines are. Models are replaceable.

Flow: **User → Objective → Understand → Plan → Execute → Verify → Report.**
Execute over explain. Automate over instruct. Complete over suggest.
True competitor is friction. North star: users think "I'll ask Aria" instead of
"I'll open an app."

## V9 priorities
1. Reliability over new capability — always.
2. Architecture before features (provider abstraction first).
3. Local-first: target 90% local / 10% cloud (MLX, Qwen 3 8B primary target;
   cloud enhances, never required). Today's reality is cloud-first — Phase B inverts it.
4. Local Knowledge Engine + background agents = strategic priorities.
5. Transparency: no black-box behavior (context inspector, workflow history,
   router dashboard planned in Phase C).

## PRESERVATION REQUIREMENT (non-negotiable)
Preserve → Improve → Expand. Never Replace → Rebuild without explicit justification.
Do not remove: blob/orb interface (core brand), wake phrase, voice interaction,
overlay UI, workflows, execution/context/memory/approval systems, visual identity.
When uncertain: additive over destructive.

## Current feature state (post-v8 + v9 phase 1)
Wake word, continuous conversation, talk-over barge-in (Speex AEC), streaming voice,
multi-step autonomy (plan→execute→verify→recover, resumable, journaled), computer use
(AX + vision fallback), ambient context (relevance-gated), Apple Mail + EventKit tools,
long-term memory, on-device behavioral learning, undo + activity log, safety gates,
multi-key Gemini rotation + Groq/Cerebras/OpenRouter/Ollama fallback,
**Proactive Presence phase 1** (Core/Proactive/: ambient suggestions, silent orb glow,
speak-on-glance — needs live mic validation), **Provider abstraction + local-first
phase B** (Core/Providers/: ModelProvider protocol, OllamaProvider (Qwen default),
GeminiProvider, DeterministicProvider (demo-mode engine), TaskClassifier +
RoutingPolicy + RoutingLog (dashboard data), LocalFirstRouter wired into
GeminiClient.generateText — opt-in via Settings "Local-first", default OFF, cloud
byte-identical until enabled; planner (.planning) is the first routed class),
**Phase C**: Local Knowledge Engine (Core/Knowledge/: opt-in folder index,
incremental by mtime, lexical search, `knowledge_search` tool, Settings →
Knowledge), background agents (Core/Agents/: daily/interval/folderChanged
triggers, silent runs through the autonomy engine + Safety gates, completion
always notifies, Settings → Agents), push-to-talk ⌥Space + Type-to-Aria ⌥⇧Space
(WakeWordEngine.summon, HotkeyManager Carbon, CommandInputPanel), Transparency
tab (context inspector / router dashboard / workflow runs).

## Safety & reliability
- Approval gates: send/pay/delete/external comms. Activity log: every action visible.
- Undo wherever possible. Fail safely, never silently.
- Assume bugs exist until proven otherwise; fault-injection tests live in
  `Tests/AriaTests/FaultInjectionTests.swift`.

## Build / test
```bash
make test            # swift test (245+ unit tests)
make release         # assemble Aria.app — ad-hoc signed
make verify-release  # guard: fails if the WMO flag is missing from release builds
make cert            # once: stable self-signed identity
make dmg             # distributable disk image
```
Requirements: macOS 14+, Xcode 16+ (Swift 6).

**Release builds MUST use `-Onone -no-whole-module-optimization`** (wired into
`make release` + `Package.swift`, guarded by `make verify-release`). The Swift optimizer
miscompiles SwiftUI actor-isolation on macOS 26.3.x: v8 hit it via WMO
(EXC_BAD_ACCESS in `swift_task_isCurrentExecutorWithFlags` on first control tap); on
**26.3.1 it returned even without WMO** (EXC_BREAKPOINT in `MainActor.assumeIsolated`
under `_ButtonGesture`, crash report 2026-06-10). Debug-level codegen has never crashed —
release is pinned to -Onone until the optimizer bug is bisected. If a first-tap crash
returns, check these flags before suspecting code. **Also:** never reinstall the v5-era
`com.aria.agent` LaunchAgent during development — KeepAlive respawns a second Aria that
fights the mic (the "works once then deaf" symptom).

**Audio-thread rule:** any closure stored in a non-actor class (AudioBus, BargeController)
runs on the audio thread and must NOT touch @MainActor properties — capture the consumers
as locals at wiring time. Violations trap only in release builds.

## Architecture (Sources/Aria/)
```
App/        AriaApp, AppDelegate (menu bar), AriaController (wiring)
Core/       WakeWordEngine, AudioBus (+Speex AEC), GeminiClient, AgentOrchestrator,
            ModelRouter, PersistencePaths
  ComputerUse/  AXReader, UIActuator, ScreenContext, VisionLocator, AXGeometry
  Autonomy/     AutonomyEngine, Safety, TaskPlan, PlanParser, IntentRouter, TaskStore
  Memory/       MemoryCapture, LongTermMemory
  Learning/     PatternEngine, PatternDetector, ObservationLog
  Proactive/    ProactiveEngine, SignalProviders, SuggestionPresenter, ProactiveStore (v9)
  Providers/    OpenAI-compatible fallback (Groq/Cerebras/OpenRouter/Ollama)
  Audio/        EchoCanceller, BargeController, SpeakerGate/Verifier, VoiceActivity
  Licensing/    LicenseManager, UpdateChecker
Tools/      AriaTool impls — System, Apps, ComputerUse, Intelligence, EventKit, SubAgents
UI/         IslandView (the blob), IslandViewModel, SettingsView, OnboardingView
Utilities/  KeychainManager, PermissionsManager, AppSettings, Logger, Theme
Sources/CSpeexDSP/  vendored Speex echo canceller (C)
site/       marketing website — React + Vite + framer-motion, cream editorial
            (approved design — preserve, animate, enhance; never redesign)
```
Stack: Swift 6, SwiftUI + AppKit, async/await + actors, MVVM.

## Working rules
- Keep the suite green. TDD for new logic (this repo tests heavily).
- Additive over destructive. Preserve brand + behavior.
- Regression validation before claiming any feature complete.
- Commit/push only when asked.
