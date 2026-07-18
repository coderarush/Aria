# Private Resume Notification Design

## Goal

Keep restart reminders useful without revealing an unfinished task's goal,
steps, inputs, or outputs in a macOS system notification.

## Decision

When Aria discovers a resumable task after launch, its optional system
notification will say only that unfinished work is ready to resume and direct
the user to Home or the existing voice command. It may include the number of
remaining steps because that does not identify the task. The task goal and
next-step summary remain visible only in Aria's Home window and in the
confirmation shown after the user explicitly chooses Resume.

## Alternatives considered

1. Keep the current goal-bearing notification. Rejected because macOS
   notifications can be seen outside the application.
2. Add a setting to opt into task names in notifications. Rejected for now:
   privacy-safe behavior should be the default and a new preference adds UI
   without improving the principal resume path.
3. Use generic notification copy and preserve detailed in-app context.
   Chosen: it protects lock-screen privacy while retaining a clear route back
   to the task.

## Components and data flow

`PersistedTask` remains the authoritative execution snapshot. A small,
pure `ResumeNotificationPresentation` maps only `unfinishedCount` to generic
notification text. `AriaController.offerResumeIfPending()` uses that mapping
after it has checked both the persisted task and the existing
`app.notifyResume` preference. It never passes the task goal to `Notifier`.

The Home task-continuity card and explicit `confirmResume(_:)` flow are
unchanged. They continue to display metadata only after the user opens Aria
or initiates a resume action.

## Error handling and compatibility

There is no new persistence, permission, or network dependency. If no pending
task exists or reminders are disabled, no notification is sent. Existing task
snapshots decode unchanged.

## Tests

Unit tests cover singular/plural generic body text and assert that a task goal
cannot appear in the generated notification text. Existing task persistence
and Home-resume tests remain the regression coverage for the detailed,
user-initiated path.
