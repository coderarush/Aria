# Contributing to Aria

Thanks for helping build the best open-source AI agent for the Mac.

## Dev setup

```bash
make build   # compile
make test    # run tests — keep these green
make run     # run the menu-bar app locally
```

macOS 14+, Xcode 15+ (Swift 5.9+). MVVM, async/await + actors, **no force-unwraps
in production paths**. Every tool ships with a unit test.

## Project layout

- `Sources/Aria/App` — entry point, menu bar, top-level wiring
- `Sources/Aria/Core` — engines (wake, screen, Gemini, orchestrator, memory)
- `Sources/Aria/UI` — orb + cards (SwiftUI)
- `Sources/Aria/Tools` — tool implementations (growing)
- `Sources/Aria/Utilities` — keychain, permissions, logging
- `Tests/AriaTests` — XCTest

## Adding a new tool

Tools are the unit of capability. The `AriaTool` protocol (landing with the
tool system) looks like:

```swift
protocol AriaTool {
    /// Stable identifier the model references in `actions[].tool`.
    static var name: String { get }
    /// One line the model reads to decide when to use this tool.
    static var description: String { get }
    /// Whether running this needs explicit user confirmation (delete, send, …).
    var isDestructive: Bool { get }
    /// Execute with the model-provided input; return a result string.
    func run(input: [String: String]) async throws -> String
}
```

To add one:

1. Create `Sources/Aria/Tools/<Category>/MyTool.swift` conforming to `AriaTool`.
2. Give it a clear `name` and a `description` the model can act on.
3. Mark `isDestructive = true` for anything that deletes, sends, or posts —
   Aria will confirm with the user before running it.
4. Register it in the tool registry (`AgentOrchestrator`).
5. Add a unit test in `Tests/AriaTests/ToolTests/MyToolTests.swift`. Mock any
   side effects; never hit a real network/file in a unit test.
6. Document it in the README tool list.

### Tool guidelines

- Keep each tool **single-purpose** with a well-defined input/output.
- No hardcoded user-facing strings scattered around — use constants.
- Long-running work uses async/await; honor cancellation.
- Respect privacy mode (no screen access when disabled).

## Pull requests

- One logical change per PR.
- `make test` must pass.
- Update README/roadmap if you add a user-visible capability.

## Code style

Match the surrounding code: rounded comments explaining *why*, small focused
files, descriptive names. If a file is growing past one clear responsibility,
split it.
