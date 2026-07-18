# Adaptive Operator Design

## Decision

Aria will add an adaptive runtime and a native command-center surface without
replacing the existing orb, voice, safety, or execution systems. The runtime
will make conservative, explainable choices from the Mac's capabilities and
current operating conditions; it will never silently change a user-selected
model to a larger or less private one. The command center will make those
choices, dependencies, and task outcomes legible at a glance.

The initial implementation is divided into independently shippable vertical
slices. This avoids a new parallel agent stack and keeps existing safety,
routing, receipts, and settings as the sources of truth.

## Audit Evidence

- `make test` executes 1,541 tests with no failures on the M4 / 16 GB machine.
- Aria's current hardware recommendation is static: `HardwareProfiler` selects
  solely from RAM and available disk. It has no notion of AC/battery power,
  Low Power Mode, thermal state, memory pressure, or measured local latency.
- `LocalFirstRouter` already owns the local/cloud decision and records model
  health, so adaptation belongs ahead of that decision rather than in tool
  implementations.
- The live controller already uses context, session continuity, intent ranking,
  trust policy, recovery, and the Live Loop. They are not duplicate backlog
  work.
- The native app window already has a polished sidebar and Home pane, but has
  no single truthful summary of readiness: permissions, connector availability,
  local-model health, runtime posture, and current recovery action are split
  across settings and secondary panes.

## Goals

1. Make Aria responsive and battery-conscious on every supported Apple-silicon
   Mac without weakening privacy or safety.
2. Route local work only when its expected performance and operating cost are
   acceptable, with a cloud fallback when configured and required.
3. Make each computer-use action verifiable, recoverable, and explainable.
4. Surface truthful capability health in a recognizably macOS-native home
   experience.
5. Create deterministic quality measurements that prevent regressions in
   routing, execution, and recovery.

## Non-goals

- Do not remove the orb, wake phrase, voice, overlays, existing model controls,
  approval gates, receipts, or undo.
- Do not auto-install models, change selected privacy settings, or turn on
  autonomous actions.
- Do not invent simulated hardware performance metrics. Measurements must be
  observed or the runtime must report the data as unavailable.
- Do not add a server or account requirement.

## Architecture

### 1. Adaptive runtime foundation

`RuntimeCapability` is a Sendable, Codable snapshot containing static capacity
(chip, RAM, free disk) and dynamic conditions (power source, battery level,
Low Power Mode, `ProcessInfo.ThermalState`, available memory when readable, and
the most recent local-model health sample). It has a pure fixture-friendly
constructor so policy tests never read the host machine.

`RuntimePosture` is a small policy result: `.performance`, `.balanced`,
`.batterySaver`, `.cooldown`, or `.constrained`. It contains a local work
allowance, recommended planning and voice model tiers, a concurrency limit,
and a concise reason fit for UI and routing logs. `RuntimePolicy.select` is
pure and deterministic:

- critical thermal state or severe memory/disk pressure → `.constrained`, no
  local planning; cloud fallback remains available;
- serious thermal state or Low Power Mode with low battery → `.cooldown`, only
  short local work, no model warming;
- battery with sufficient charge → `.batterySaver`, small/fast local models and
  one concurrent local request;
- AC power with normal conditions → `.balanced` for 8–23 GB Macs and
  `.performance` only on 24 GB+ Macs with healthy disk and latency.

The thresholds are conservative, visible in code, and covered by a complete
table of tests. A user-selected model remains preferred when it is compatible
with the posture; the policy may only step down or defer it.

`RuntimeAdvisor` is an actor that samples dynamic state at startup, on power
and thermal notifications, and at a low-frequency cadence. It persists no raw
activity data. It publishes the latest snapshot and posture to the router and
the UI. Dependency injection isolates IOKit/ProcessInfo reads for tests.

### 2. Adaptive local routing

`LocalFirstRouter` consumes a `RuntimeAdvisor` snapshot before probing Ollama.
For constrained work it returns a cloud decision with an explicit reason; it
does not start or warm a model. For allowed local work it uses the effective
model resolved by the posture, then preserves the existing availability check,
health recording, and cloud fallback. Routing logs include the runtime posture
and reason, making each decision inspectable.

### 3. Verified execution

Computer-control actions receive an optional `PostCondition` derived from the
tool action. A verifier first checks the accessibility tree, then uses a
targeted visual fallback only when needed. It records evidence and verification
state in the existing action receipt. An unverified action is never represented
as completed: Aria retries through the existing recovery loop or reports what
could not be proven. Destructive actions retain their existing confirmation
requirements.

The first slice supports deterministic conditions that are already observable:
frontmost app, focused field/value, window geometry, and displayed text. It
does not pretend arbitrary canvas work has been verified.

### 4. Native command center

The Home pane gains a compact "Aria status" card with five human-facing facts:
runtime posture, local model readiness and last latency, permissions needing
attention, connected services, and the currently running/recovering task.
Each fact is actionable and names the outcome rather than implementation
internals. The visual system uses existing `AriaCard`, system materials,
SF Symbols, Dynamic Type-compatible system fonts, subdued semantic colors,
keyboard focus, and Reduce Motion. The orb remains the primary identity; the
card is a calm instrument panel, not a dashboard redesign.

### 5. Continuous evaluation

The deterministic assistant benchmark becomes a scored evaluation harness:
defined scenarios execute through real router, tool registry, safety, and
receipt seams using deterministic providers. It records outcomes in a compact
local summary. A release gate checks required scenarios for routing fallback,
receipt creation, verification failure recovery, and graceful unavailable
dependencies. It is a quality signal, not marketing copy.

## Delivery Order

1. Adaptive runtime domain types and policy tests.
2. Runtime advisor and router integration.
3. Native command-center status model and Home-pane card.
4. Verifiable computer-use postconditions and receipt evidence.
5. Evaluation harness and release gate.

Each slice must use test-first development, preserve existing behavior when
adaptation is unavailable, run the focused tests plus `make test`, and receive
a release build check before it is considered complete.

## Acceptance Criteria

- Policy fixtures cover AC, healthy battery, Low Power Mode, elevated/critical
  thermal state, low disk, low memory, and poor local-model latency.
- On critical thermal or constrained capacity, eligible work does not probe or
  start the local model and exposes a reason for its cloud/deferred route.
- On normal AC power, the existing local-first path remains usable and keeps
  cloud fallback behavior.
- The Home pane states runtime and readiness in plain language, respects Reduce
  Motion, and remains usable at its existing 900×600 minimum window size.
- A failed postcondition is visible in the receipt and reaches recovery/reporting
  rather than being recorded as a verified completion.
- The evaluation harness has deterministic pass/fail output and is included in
  the project verification path.
