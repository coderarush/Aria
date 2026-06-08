# Aria — V8 Master Engineering Directive (working context)

**Status:** Internal pre-release V8 → target V1 public launch.
**Branch:** `aria-v8`.
**Current focus:** P1 Reliability — done (single confirm gate, retry discipline,
model-outage surfacing, unified destructive gate, durable activity log + UI, undo
system). **P2 Execution speed** — major levers done: fast-model planning/recovery
(flash-lite), parallel turn setup (async let), bounded 30s request timeouts, and
on-demand `look_at_screen` vision tool replacing redundant eager screenshots
(needsScreen tightened to explicit whole-screen requests). **P3 Context awareness** —
added clipboard (relevance-gated ambient via ContextRelevance), `finder_selection` and
`browser_tabs` on-demand tools; retrieval is intentional + explainable (each tool call
shows in the activity log). **P3 email gap closed** + **P4 Cross-app workflows**: Apple Mail tools
(email_recent/search/draft + send_mail, gated) — native-macOS, works with Gmail
accounts, no OAuth; and autonomy now threads ALL prior step outputs (labeled digest,
`AutonomyEngine.material`) to agent steps so workflows synthesize across the whole
chain, not just the last result. Remaining: project context, open-doc paths, a
first-party Gmail API (future). Next candidate: P5 Persistent Memory / P6 Long-running.

## What Aria is
Execution-first intelligence + execution layer for macOS. Voice-first, keyboard-accessible.
Turns user *intent* into *completed work*. NOT a chatbot, NOT a voice wrapper around an LLM,
NOT a Siri clone.

Flow: **User → Objective → Plan → Execute → Verify → Report completion.**
Default: Execute over explain. Automate over instruct. Complete over suggest.
True competitor is manual computer work — build against friction.

## North star
Users stop thinking "I should open App X" and think "I should ask Aria."
Aria is the default intelligence/execution layer for macOS; apps become implementation details.

## PRESERVATION REQUIREMENT (non-negotiable)
V8 evolves an existing, shipped product. Existing systems are **assets, not obstacles**.
Default philosophy: **Preserve → Improve → Expand**. NEVER Replace → Rebuild without
explicit, documented justification.

Do not, without justification:
- remove existing features / workflows / functionality
- redesign systems or interfaces
- remove visual identity elements
- remove established interaction patterns
- break existing user-facing behavior (unless required for stability/security)

Before any significant architectural/UX change: audit existing impl, understand the feature's
purpose, preserve user-facing behavior, keep workflows backward-compatible, improve not replace.
When uncertain: prefer additive over destructive.

### Brand assets — treat as product, not implementation detail
The **morphing blob/orb interface**, its animations, overlays, voice interaction model,
personality, and the "alive" presence are core brand. Do not swap for a "technically simpler"
alternative. Evolve while keeping what makes Aria feel like Aria.

## V8 priorities (in order)
1. **Reliability** (reliability is a feature; stabilize existing before adding new)
2. Execution speed (fast invocation, low latency, minimal confirmations)
3. Context awareness
4. Cross-app workflows
5. Persistent memory
6. Long-running agents

Every feature must answer "Does this reduce work for the user?" If no, reconsider.

## Existing systems (improve + expand, do not remove)
Wake-phrase activation · blob interface · floating command overlay · workflow planning ·
approval gating · execution pipelines · memory systems · automation systems.

## Engines (map to source)
- **Context engine** — active app/window, visible screen, clipboard, tabs, docs, selected
  files, calendar/email/project context, history. Retrieval: efficient, intentional, explainable,
  only when relevant. → `Core/ComputerUse/` (AXReader, ScreenContext, VisionLocator), `Core/ScreenCaptureEngine`.
- **Memory engine** — user prefs, long-term, project, workflow, relationship, session memory.
  → `Core/Memory/`, `Core/ConversationMemory.swift`, `Core/Learning/`.
- **Execution engine** — system actions (apps, windows, files, search), browser actions,
  productivity actions (calendar, reminders, email, docs, notes). → `Tools/`.
- **Agentic workflow engine** (primary differentiator) — multi-step planning, workflow
  chaining (outputs→inputs), long-running agents (background, progress, notifications, retry,
  error recovery, resumable). → `Core/Autonomy/` (AutonomyEngine, TaskPlan, PlanParser,
  IntentRouter, TaskNarration), `Tools/SubAgents/`.

## Modes (same engine, modify tools/context/priority — not separate products)
Founder · Student · Developer (terminal/IDE/git/Claude Code integration).

## Integration strategy
Tier 1: Finder, Terminal, Safari, Chrome, Apple Notes.
Tier 2: Gmail, Google Calendar, GitHub, Notion, Slack.
Tier 3: more productivity tools.
Preference order: **Official APIs → native macOS → UI automation.** Favor reliability.

## Safety & reliability (reliability is a feature)
- **Approval gates** required: send email, delete files, external comms, financial, high-impact.
- **Activity logs**: every action visible + traceable.
- **Undo** wherever technically possible.
- **Recovery**: handle missing permissions, API failures, network loss, invalid context,
  interrupted workflows gracefully.
→ `Core/Autonomy/Safety.swift`, `Utilities/PermissionsManager.swift`, `Utilities/Logger.swift`.

## Build / test
```bash
make test       # 166 unit tests (swift test)
make release    # assemble Aria.app — ad-hoc signed
make cert       # once: stable self-signed identity (permissions persist across rebuilds)
make dmg        # distributable disk image
```
Requirements: macOS 14+, Xcode 16+ (Swift 6).

**Release builds MUST disable whole-module optimization** (`-no-whole-module-optimization`,
already wired into `make release` + `Package.swift`). On Swift 6.3 / macOS 26, WMO miscompiles
SwiftUI actor-isolation → crash on first tap of any SwiftUI control
(`swift_task_isCurrentExecutorWithFlags` → `objc_msgSend`, EXC_BAD_ACCESS). If that crash
returns, the WMO flag was dropped — not a code regression.

## Architecture (Sources/Aria/)
```
App/        AriaApp, AppDelegate (menu bar), AriaController (wiring)
Core/       WakeWordEngine, AudioBus (+Speex AEC), GeminiClient, AgentOrchestrator, ModelRouter
  ComputerUse/  AXReader, UIActuator, ScreenContext, VisionLocator
  Autonomy/     AutonomyEngine, Safety, TaskPlan, PlanParser, IntentRouter, TaskNarration
  Memory/       MemoryCapture, LongTermMemory
  Learning/     PatternEngine, PatternDetector, ObservationLog
  Providers/    OpenAI-compatible fallback (Groq/Cerebras/OpenRouter/Ollama)
  Audio/        EchoCanceller, BargeController, SpeakerGate/Verifier, VoiceActivity
  Licensing/    LicenseManager, UpdateChecker
Tools/      AriaTool impls — System, Apps, ComputerUse, Intelligence, EventKit, SubAgents
UI/         IslandView + MorphingBlobView (the orb), IslandViewModel, SettingsView, OnboardingView
Utilities/  KeychainManager, PermissionsManager, AppSettings, Logger, Theme
Sources/CSpeexDSP/  vendored Speex echo canceller (C) — far-end ref for talk+listen
```
Model: Gemini free tier (key rotation), fallback Groq/Cerebras/OpenRouter, Ollama offline.
Stack: Swift 6, SwiftUI + AppKit, async/await + actors, MVVM.

## Working rules
- Keep the suite green. Add tests for new logic (this repo tests heavily).
- Additive over destructive. Preserve brand + behavior.
- Commit/push only when asked.
