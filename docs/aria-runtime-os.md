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

## Part 4 — Perception, multimodality, device mesh, Glass substrate (Waves A–G)
Built additively per Master Build Spec Part 4 (§§68–87). 29 new TDD tests, green.
New top-level `Perception/` and `Mesh/` layers.

| Layer | Type(s) | Spec |
|---|---|---|
| Perception OS | `Observation`, `ObservationPolicy`, `ObservationBus`, `PerceptionStore`, `PerceptionEngine` | §69/70/83 |
| Modality | `ScreenContextEngine`, `AudioContextEngine`, `VisualContextEngine` | §72-74 |
| Fusion | `FusionEngine`, `ConflictResolver`, `UnifiedContext` | §75 |
| Attention V2 | `ActivityDetector`, `ActivityMode` | §76 |
| Mesh | `DeviceMesh`, `MeshDevice`, `ContextHandoff`, `HandoffBundle` | §77/78 |
| Glass | `GlassRuntime`, `HUDState` | §79/80 |
| Recall | `RecallEngine`, `RecallBundle` | §81 |
| Knowledge | `KnowledgeEngine`, `KnowledgeNode`/`Edge` | §82 |
| Eval | `PerceptionHarness` (95% relevance target) | §84 |

**Perception produces observations, never actions** (§69). **No raw media
retained** — screenshots/audio/frames are summarized to structured observations
only (§72-74/83); observations are bounded, visible, deletable. Glass is
software-only and works without hardware (§86); it consumes context and displays
awareness with no execution/tools. Release gate proven in `Part4HarnessGateTests`
(§86). Camera / wearable hardware / Glass execution / full autonomy deliberately
NOT built (§87 stop).

## Part 5 — Delegation, executive function, identity, second brain (Waves A–G)
Built additively per Master Build Spec Part 5 (§§88–106). 35 new TDD tests, green.
New top-level `Executive/` layer.

| Layer | Type(s) | Spec |
|---|---|---|
| Executive | `ExecutiveEngine`, `DelegationEngine`, `DelegationContract` | §89/90 |
| Adaptive | `AdaptiveExecution`/`ExecutionProfile`, `ObjectiveMarket`, `ExecutionPolicyEngine`/`ExecutionPolicySet` | §91/92/93 |
| Identity | `IdentityEngine`/`InteractionProfile`, `ProductMemory` | §94/95 |
| Workflow/Artifact | `WorkflowEngine`/`ReusableWorkflow`, `ArtifactEngine`/`VersionedArtifact` | §96/97 |
| Initiative | `InitiativeEngine` (ceiling awaitApproval), `ReviewEngine`/`ClosureReport`, `HorizonEngine` | §98/99/100 |
| Glass/Command | `GlassExperience`, `CommandModel` | §101/102 |
| Eval | `ExecutiveHarness` | §103 |

**Authority is earned, never assumed** (§88): `ExecutiveEngine` executes only
when `authority.allowsExecution`, else parks at `.review` for approval.
**Initiative never executes** — ceiling is awaitApproval (§98/106). Identity
never simulates emotion or personhood (§94). ProductMemory keeps bounded
summaries, no transcripts (§95). Glass experience displays only — no execution/
planning/tools (§101). Release gate proven in `Part5HarnessGateTests` (§105).
AGI / friendship simulation / approval removal / autonomous execution
deliberately NOT built (§106 stop).

## Part 6 — Productization, reality, trust, adoption (Waves A–G)
Built additively per Master Build Spec Part 6 (§§107–127). 30 new TDD tests, green.
This part integrates/measures rather than adding engines (§108).

| Layer | Type(s) | Spec |
|---|---|---|
| Migration | `MigrationController`, `MigrationDecision` | §109 |
| Quality | `ExecutionQuality`/`ExecutionScore`, `TimeEngine` | §110/113 |
| Trust/Failure | `TrustDashboard`, `FailureExperience` | §115/116 |
| Onboarding | `OnboardingEngine`, `DefaultExperience` | §117/118 |
| Product | `DelightEngine`, `HabitEngine`, `FeedbackEngine`, `AnalyticsEngine` | §111/112/114/121 |
| Ops | `DogfoodEngine`, `LatencyBudget`, `ReleaseEngine`, `GlassReadiness` | §119/120/122/123 |
| Eval | `DeleteAnalyzer`, `ProductHarness` | §124/125 |

`MigrationController` promotes on ≥95% parity / rolls back on regression — but
the real flip needs on-device parity data. Delight never interrupts/manipulates/
gamifies (§111); analytics is metadata-only (§121); failures never blame the
user (§116). **DeleteAnalyzer identifies dead code but never deletes** — the
legacy path is preserved until the migration reaches `.cleanup` (§50/124), so
removal stays a deliberate reviewed step. Release gate proven in
`Part6HarnessGateTests` (§126). No new agents / AGI / architecture (§127 stop) —
this part is about shipping.

## All six spec parts executed
Parts 1–6 of the Aria Master Build Spec are implemented on `runtime-os`: topology
reorg + a full execution-first runtime, memory/continuity/presence, perception/
multimodality/mesh/Glass, executive/delegation/identity, and productization/
migration tooling. ~1386 tests, all green except the pre-existing
`ConnectorStoreActorTests` baseline (2).

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

## Live Loop (2026-07-02)

The approved 2026-06-24 design is now built and wired (`Presence/Live/`):

| Piece | Type(s) |
|---|---|
| Playbooks | `PlaybookRef`, `Playbook`, `PlaybookLibrary` (bind-or-fail templates), `AutonomyTier` (auto/confirm/off) |
| Signals | `ClockSignal`, `CalendarSignal` (EventKit), `MailSignal` (Gmail unread delta, ≥5-min cadence), `ScreenActivitySignal` (event-driven app ping-pong) |
| Recognizers | `MeetingPrepRule`, `InboxTriageRule`, `ScreenCoPilotRule`, `DailyBriefRule` — pure `OpportunityRule`s carrying a `PlaybookRef` |
| Runtime | `LiveLoop` actor (events + idle tick, quiet-hours + Low Power + cooldown/snooze/never gates), `LiveLoopSettings`, `LiveLoopStore` |

Auto tier dispatches through `AriaController.handleCommand(unattended:)` (the
existing orchestrator + Safety); confirm tier rides the existing
`SuggestionPresenter` card — one live card ever. Outcomes land in
`LongTermMemory`. Settings → Proactive hosts the master toggle + per-recognizer
tier pickers. Kill switch: `defaults write com.aria.agent app.disableLiveLoop -bool true`.

Also shipped alongside: 7 everyday tools (timer, weather, music_control,
contacts_search, window_arrange, clipboard_history, system_status), standing
instructions (`CustomInstructions`), `SoundTheme` chime voicings, 4 new glow
palettes, `LocalVoice` offline-voice ranking + picker, and idle-energy fixes
(HUD cursor timer scoped, hero blob 30 fps + Reduce Motion).
