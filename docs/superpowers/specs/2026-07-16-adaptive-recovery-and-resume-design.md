# Adaptive Recovery and Confirmed Resume Design

## Goal

Make Aria adapt truthfully to the current Mac, recover from temporary local
model trouble, and give a person a native, deliberate way to resume interrupted
work from Home.

## Scope

This slice has three linked improvements:

1. Read a conservative estimate of currently reclaimable memory on macOS, so a
   capable AC-powered Mac can actually enter the existing Performance posture.
2. Replace lifetime-only local-model health with a bounded, recent observation
   window. Planner, live chat, and warm-up activity all report outcomes. A short
   failure streak should reduce local work; successful recent work should let it
   recover without an app relaunch.
3. Add a Home-card Resume control for persisted tasks. It first presents a native
   confirmation describing the privacy-safe next step; it never automatically
   starts work on launch or exposes raw task input/output.

Mirror Bridge remains a separate networking project: its current settings must
not imply a working network bridge until a listener, pairing/authentication, and
transport tests exist. That work follows this runtime/continuity slice.

## Architecture

### Runtime signal

`RuntimeSignalReader.live` gains a direct macOS memory reading based on
`sysctlbyname` virtual-memory page counters and the host page size. The signal is
an estimate of reclaimable memory (free + inactive + purgeable pages), rounded
down to whole GiB. If any read is unavailable or inconsistent, it returns `nil`;
the policy keeps its existing conservative balanced fallback.

No shell process is spawned. Existing injected signal closures keep policy tests
fully deterministic.

### Recent local-model health

`LocalModelHealth` records timestamped observations in a fixed-size recent
window. Its snapshot retains the existing public counters for UI continuity and
adds enough recent-window data for the runtime advisor to calculate a recent
failure rate. The advisor uses the recent rate only after a minimum observation
count, so one transient failure does not immediately disable planning forever.

The router records planning outcomes as it does today. The streaming local-chat
path and background warm-up record success/failure with measured duration, and
release their shared local-work slot on every exit. This lets cooldown respond to
real current conditions rather than stale lifetime history.

### Confirmed Home resume

The desktop shell posts a dedicated `aria.resumeTask` notification from a
visible Resume button only when a task is resumable. `AriaController` observes
it, checks that no task or confirmation is already active, reads the pending
task, and uses the existing native confirmation presenter. The prompt identifies
the goal and next summary only; confirmation calls the existing `resumeTask`
execution path. Cancel leaves the persisted task unchanged.

The control does not run for a task marked as currently running, and it does not
change the existing voice "resume" path.

## Error handling and safety

- Missing memory telemetry remains conservative rather than guessing.
- Health observations are bounded and in-memory only; no model prompts, output,
  or user content is stored.
- A busy controller ignores duplicate Resume requests.
- A stale/missing persisted task produces an honest response rather than an
  assumed success.
- Resume still uses the existing per-action safety gates and postconditions.

## Verification

- Unit-test live-memory arithmetic through injected page-counter values.
- Unit-test health-window expiry/minimum-sample behavior and policy recovery.
- Unit-test chat/warm-up observation reporting with injected deterministic
  providers where their seams permit it.
- Unit-test notification-to-confirmation resume dispatch with injected task and
  confirmation dependencies.
- Run focused tests, `make test`, `make evaluate`, `make release`, deep
  code-sign verification, and `git diff --check`.
