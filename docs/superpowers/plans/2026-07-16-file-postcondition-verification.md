# File Postcondition Verification Plan

**Goal:** Let Aria verify that a local file it was asked to save actually
exists, before representing the step as complete.

## Scope

- Add one explicit, planner-whitelisted `file_exists` postcondition with a
  target path.
- Accept it only on a `file_write` step whose input path matches exactly, so an
  unrelated existing file cannot become false proof.
- Check only metadata (`FileManager.fileExists`); never read the file or put its
  contents into task output, receipts, or telemetry.
- Reuse the existing bounded postcondition retry and recovery path.
- Preserve the existing default behavior for plans with no verifier.

## Acceptance checks

1. The parser accepts a nonempty `file_exists` path and rejects malformed
   variants.
2. The injected verifier reports a concise proof for both present and missing
   paths.
3. A mismatched path or non-file-write step is rejected by the parser.
4. The condition survives Codable persistence.
5. Focused, full, release, signature, and whitespace checks pass.
