# Truthful Research Save Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Report a research file as saved only after the write succeeds.

**Architecture:** Return `ResearchOutcome(report:savedURL:)` from the engine;
the optional URL is the sole persistence success signal. The tool maps it to
truthful user-facing completion text.

**Tech Stack:** Swift 6, Foundation file I/O, XCTest.

## Global Constraints

- Preserve a generated report when saving fails.
- Do not write research-test artifacts to the user’s Documents directory.
- Do not stage, commit, or modify unrelated user changes.

---

### Task 1: Make report persistence observable and testable

**Files:**
- Modify: `Sources/Aria/Services/Browser/ResearchEngine.swift`
- Modify: `Tests/AriaTests/ResearchEngineTests.swift`

**Interfaces:**
- Produces: `ResearchOutcome(report: ResearchReport, savedURL: URL?)`
- Consumes: `ResearchEngine.reportsDirectory: URL`
- Used by: `ResearchTool.run(input:)`

- [ ] **Step 1: Write failing success and failure tests**

```swift
let outcome = await engine.research(topic: "topic") { _ in reportJSON }
XCTAssertNotNil(outcome.savedURL)
XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.savedURL!.path))

let failed = await blockedEngine.research(topic: "topic") { _ in reportJSON }
XCTAssertNil(failed.savedURL)
XCTAssertEqual(failed.report.topic, "topic")
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `swift test --filter ResearchEngineTests`

Expected: compilation failure because `ResearchOutcome` and injected report
directory are not defined.

- [ ] **Step 3: Add outcome and atomic save result**

```swift
struct ResearchOutcome: Sendable {
    let report: ResearchReport
    let savedURL: URL?
}

private func saveReport(_ report: ResearchReport, topic: String) -> URL? {
    do {
        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        let destination = reportsDirectory.appendingPathComponent(filename)
        try JSONEncoder().encode(report).write(to: destination, options: .atomic)
        return destination
    } catch {
        Log.trace("research: report save failed")
        return nil
    }
}
```

- [ ] **Step 4: Run focused tests to verify they pass**

Run: `swift test --filter ResearchEngineTests`

Expected: all research-engine tests pass without persistent Documents artifacts.

### Task 2: Report save status truthfully from the tool

**Files:**
- Modify: `Sources/Aria/Execution/Actions/ResearchTool.swift`
- Test: `Tests/AriaTests/ResearchEngineTests.swift`

**Interfaces:**
- Consumes: `ResearchOutcome.report` and `ResearchOutcome.savedURL`
- Produces: a `ToolResult` that says either `Saved to <path>.` or `Not saved locally.`

- [ ] **Step 1: Replace unconditional success copy**

```swift
let outcome = await engine.research(topic: topic, maxSources: maxSources) { prompt in
    try await gemini.generateText(prompt: prompt, temperature: 0.3)
}
let summary = "Research complete on '\(topic)': \(outcome.report.sections.count) sections, \(outcome.report.sources.count) sources used."
if let url = outcome.savedURL {
    return .ok("\(summary) Saved to \(url.path).")
}
return .ok("\(summary) Not saved locally.")
```

- [ ] **Step 2: Run completion verification**

Run: `make test && make evaluate && make release && codesign --verify --deep --strict .build/Aria.app && git diff --check`

Expected: full suite, evaluation gate, package, signature, and whitespace
checks succeed. Do not commit because no commit was requested.
