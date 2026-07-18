# Truthful Research Save Design

## Goal

Ensure Aria never reports that a research report was saved unless its JSON file
was successfully created, while still returning usable research when local
persistence fails.

## Decision

`ResearchEngine.research` will return a `ResearchOutcome`: the generated
`ResearchReport` and an explicit `savedURL` that is non-nil only after both the
report directory creation and atomic file write succeed. A failed save is not a
research failure; it produces the report with `savedURL == nil`.

`ResearchTool` will use that value in its completion text. Success identifies
the saved file. Failure clearly says the research is available in the current
response but was not saved locally. It will not fabricate a path.

## Alternatives considered

1. Preserve the current unconditional “Saved.” message. Rejected because it
   makes an externally observable claim without a postcondition.
2. Fail the entire research task on a save failure. Rejected because search and
   synthesis may have succeeded and the result remains useful.
3. Return the report with a separate optional saved URL. Chosen: it keeps the
   useful result and makes persistence verifiable by callers.

## Components and data flow

`ResearchEngine` owns report generation plus a configurable report directory.
Its private save helper returns an optional file URL and logs the failure
without exposing an error description to the user. `ResearchOutcome` is a
small Sendable result value with `report` and `savedURL`.

`ResearchTool` presents saved/not-saved text based entirely on `savedURL`.
No other planning or model behavior changes.

## Error handling and tests

Tests inject temporary directories: one valid directory verifies a file and
the returned URL; one regular file used as a directory verifies the report is
still returned with no saved URL. Existing parsing, deduplication, and
synthesis-fallback tests continue to validate report content.
