# Aria V9 Pre-Release — Implementation Roadmap

Governing docs: [ARIA_V9_MASTER.md](ARIA_V9_MASTER.md) (product/engineering constitution),
[ARIA_WEBSITE_V9.md](ARIA_WEBSITE_V9.md) (website constitution), `ariawebsitedesign.png`
(approved design reference).

Philosophy: **Preserve → Improve → Expand.** Architecture before features. Reliability
before new capability. No feature removal in any phase.

## Phase A — Stabilize & Consolidate (Preserve)

1. ✅ Split + commit the entangled working tree (hardening pass `edda9dc`, Proactive
   Presence phase 1 `22252dd`).
2. ✅ Constitution docs archived into `docs/v9/`; CLAUDE.md rewritten as V9 working context.
3. ✅ Debt: enforce sub-agent `allowedTools`; consolidate Application Support path helpers
   onto `PersistencePaths`; remove dead `website/` after reference check.
4. ✅ WMO guard: `make verify-release` fails if `-no-whole-module-optimization` is dropped
   (the Swift 6.3/macOS 26 SwiftUI tap-crash regression).
5. ✅ Failure-simulation seed: fault-injection tests (malformed provider responses,
   permission-denied paths, interrupted workflow resume).
6. ⬜ Live device validation (requires the user at the mic): proactive reveal-on-wake +
   accept-by-voice + orb glow; launch resume notification; barge-in regression sweep.
7. Retire the stale `~/Desktop/Friday` checkout (constitution files now archived here).

## Phase B — Architectural Spine: Provider Abstraction + Local-First (Improve)

- `Provider` protocol (generate/stream/tools/vision capabilities); wrap — don't rewrite —
  `GeminiClient` and `OpenAICompatibleClient`; thin Claude/OpenAI configs.
- `LocalProvider`: MLX runtime, Qwen 3 8B primary (constitution target), Ollama kept.
- ModelRouter v2: task-class local/cloud routing with logged decisions (model, reason,
  classification — feeds the Router Dashboard). Cloud remains automatic fallback; the
  Gemini path stays default until a task class proves itself locally.
- `DeterministicProvider` behind the same protocol — the engine for ARIA_DEMO_MODE.

Risks: local 8B tool-calling quality, MLX-Swift maturity, 16 GB memory pressure.
Gate: side-by-side eval harness; a task class only routes local when it matches cloud.

## Phase C — Capability Expansion (Expand)

1. **Local Knowledge Engine** — incremental, privacy-first local index of PDFs/notes/
   docs/repos/projects; `knowledge_search` tool + ambient project context.
2. **Background agents** — scheduler over TaskStore/AutonomyEngine: folder monitoring,
   daily briefing, recurring workflows; delivery through the Proactive presenter;
   every run visible in workflow history.
3. **Interaction layer** — global push-to-talk (coexists with wake phrase) + typed input.
4. **Transparency** — Context Inspector, Workflow History, Model Router Dashboard.
5. **Proactive phase 2** — Command + Screen signal providers (screen off by default).

## Phase D — Productization (Expand → Ship)

- ARIA_DEMO_MODE (DeterministicProvider + scripted workflows; never fails on camera).
- Website per constitution (Preserve → Animate → Enhance): waitlist funnel, blob
  scroll-storytelling, outcome-first demo recordings, Local-Intelligence/Knowledge/
  Background-Agents sections, founder + developer workflows, SEO/a11y/perf pass.
- Licensing decision (trial on/off for pre-release), `make dmg` re-verify, notarization
  when the Apple Developer account exists.

## Highest-leverage order

Provider abstraction (B) → Knowledge Engine (C1) → Background agents (C2) →
push-to-talk/typed input (C3) → demo mode + website (D).
