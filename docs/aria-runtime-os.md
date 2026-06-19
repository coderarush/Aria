# Aria Runtime OS

Status of the execution-first runtime layer built per the **Aria Master Build
Spec** (Part 1, §§6–24). Branch: `runtime-os`.

## What shipped (Waves 1–9)

The repo was restructured into the spec §6 topology and a tested runtime spine
was built additively on top of the existing app. All new code is TDD'd
(63 new tests, all green; full suite green except the pre-existing
`ConnectorStoreActorTests` baseline).

### Topology (Wave 2)
All 256 source files migrated from feature folders into the spec topology —
`Application / Runtime / Execution / Intent / Planning / Context / Memory /
Presence / Permissions / Observability / Services / Core / UI`. Single flat
SwiftPM target, so folder moves don't affect compilation. Full mapping:
`docs/aria-migration-map.tsv`.

### Runtime spine
| Layer | Type(s) | Spec |
|---|---|---|
| Events | `AriaEvent`, `EventBus` (actor, async fan-out, bounded replay) | §12 |
| Runtime | `RuntimeState` (7 states), `AriaRuntime` (single-authority actor) | §10 |
| Boot | `AppBootstrapper`, `RuntimeContainer` | §8 |
| Domain | `Domain.{Objective,Task,Action,Artifact,ContextSnapshot,Memory}` | §7 |
| Execution | `ExecutionGraph` (DAG), `ExecutableTool`, `ExecutionSupervisor`, `ExecutionEngine`, `Verifier` | §13/14/17 |
| Intent/Plan | `ObjectiveEngine`, `Planner`/`SequentialPlanner`, `ExecutionPlan` | §15/16 |
| Context | `ContextContributor`, `ContextCollector` | §7 |
| Memory | `MemoryStore` | §7/18 |
| Presence | `PresenceRule`, `PresenceDetector`, `PresenceOpportunity` | presence |
| Observability | `MetricsCollector`, `ExecutionTimeline` | §22 |
| Config/Storage | `FeatureFlags`, `KeyValueStore`/`InMemoryKeyValueStore` | §18/19 |

### Proven end-to-end
`RuntimeIntegrationTests` drives the full spine through `RuntimeContainer`:
boot → `createObjective` → `SequentialPlanner.plan` → `ExecutionEngine.execute`
→ `Verifier` → metrics/timeline drain → objective complete. Everything shares
one `EventBus`.

## Part 2 — Memory OS, Continuity, Presence (Waves A–G)
Built additively on the Part 1 spine per Master Build Spec Part 2 (§§25–48).
37 new TDD tests, all green.

| Layer | Type(s) | Spec |
|---|---|---|
| Memory OS | `MemoryRecord`, `ImportanceScorer`, `MemoryEngine`, `ContextualRetrieval` | §27–31 |
| Continuity | `Checkpoint`, `CheckpointManager`, `ContinuityEngine` | §32 |
| Projects | `ObjectiveTracker`, `Project`, `ProjectEngine` | §33/34 |
| Context V2 | `ContextEnvelope`, `ContextConfidence`, `ContextAssembler` | §35/36 |
| Presence | `Opportunity`, `OpportunityDetector`, `OpportunityRanker`, `PresenceSuggestion`, `SuggestionEngine`, `PresenceEngine` | §37–39 |
| Attention | `AttentionAssessment`, `AttentionAssessor` | §40 |
| Learning | `LearningEngine` (no self-modify) | §43 |
| Autonomy | `AutonomyLevel` (default `.suggest`) | §44 |

**Release gate proven** (`Part2ReleaseGateTests`, §47): stop → return → continue
→ trust suggestions → recover, plus memory retrieval by objective+keyword.
Presence **notices, never executes** (§42/§48). Proactive execution / autonomy /
Glass intentionally NOT built (§48 stop).

## Deferred (next waves)
- **Live wiring**: the new runtime is built + tested but not yet the app's live
  execution path; `AriaController`/`AgentOrchestrator` still drive production.
  Bridging existing `AutonomyEngine`/`GoalEngine`/`ToolRegistry`/`AriaTool` onto
  the `EventBus` + `ExecutableTool` is the main remaining integration.
- **Execution**: parallel/speculative modes + hard per-action timeouts
  (serial + retry are live).
- **Storage**: SQLite-backed `KeyValueStore`/`MemoryStore` (in-memory seam today).
- **Config**: Experiments + Policies beyond `FeatureFlags`.
- **Presence acting** + Glass prep (Part 3 / spec Phase 5) — deliberately deferred.
