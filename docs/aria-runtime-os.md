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

## Part 3 — Live migration, trust, observability, surface (Waves A–H)
Built additively per Master Build Spec Part 3 (§§49–67). 46 new TDD tests, green.

| Layer | Type(s) | Spec |
|---|---|---|
| Migration | `MigrationStage`, `LegacyExecutor`/`RuntimeExecutor`, `RuntimeBridge`, `ExecutionDiff` | §51 |
| Shadow | `ShadowExecution`, `ParityReport` (95% gate) | §52 |
| Permissions | `PermissionOS`, `PermissionType`/`Scope`, `ConsentLedger` | §54 |
| Trust | `TrustEngine` (confidence, not autonomy) | §55 |
| Governance | `ToolGovernor` (`ToolHealth`), `CapabilityMatrix` | §53 |
| Coordination | `Coordinator` (plan→execute→verify→remember, no swarms), `ExecutionContract` | §59/60 |
| Observability | `AriaInspector`, `ReplayEngine` | §56 |
| Evaluation | `Scenario`, `ScenarioLibrary`, `EvaluationHarness` | §61 |
| Recovery | `RecoveryEngine` (checkpoint/recover/rollback/failover) | §62 |
| Surface | `SurfaceKind`/`SurfaceProtocol`, `ExperienceLayer`, `StreamState`, `ContextStream`, `ObjectiveWorkspace`, `ExecutionSurfaceState` | §57/58/64/65 |

**Migration is staged + reversible** (legacy→shadow→dual→preferred→runtimeOnly→
cleanup); shadow runs the runtime silently and gates promotion on 95% parity.
Surfaces render only, never execute. Glass / camera / wearable / autonomous
execution deliberately NOT built (§67 stop). Release gate proven in
`Part3ReleaseGateTests` (§66).

## Deferred / human-gated
- **Production flip**: the bridge, adapters, shadow, and parity gate exist and
  are tested, but `LegacyExecutor`/`RuntimeExecutor` are not yet wired to the
  real `AgentOrchestrator`/runtime, and the stage is not advanced past `.legacy`
  in production. Flipping requires conforming the real paths to the seams and
  validating ≥95% parity on a real device — a human + device step, by design.
- **Execution**: parallel/speculative modes + hard per-action timeouts.
- **Storage**: SQLite-backed `KeyValueStore`/`MemoryStore` (in-memory seam today).
- **Config**: Experiments + Policies beyond `FeatureFlags`.
- **Glass / hardware**: out of scope by spec (§67).
