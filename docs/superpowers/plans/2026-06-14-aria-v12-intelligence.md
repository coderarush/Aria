# Aria v12 "Intelligence" — Implementation Plan

Branch: `aria-v12`  
Worktree: `~/Aria/.worktrees/aria-v12`  
Baseline: 779 tests green  

## Context

Four capability upgrades derived from Aria's self-assessment. Codebase is Swift/macOS, 
actor-isolated throughout. Key existing infrastructure:

- `Core/Proactive/` — CalendarSignalProvider, ProactiveEngine, Suggestion model
- `Core/Recipes/` — Recipe, RecipeStore, WorkflowPack (deterministic tool-step playbooks)
- `Core/Connectors/` — OAuth2 PKCE for Google/Notion/Slack; ConnectorID enum; ConnectorTokenStore
- `Tools/Intelligence/` — gmail_recent, gcal_upcoming, notion_search, drive_search, slack_recent etc.
- `Core/AgentOrchestrator.swift` — multi-step tool loop, runRecipe(), runPlan()
- `Core/GeminiClient.swift` — generateText(), streamSend() with provider fallback

All new files go in the worktree. Every task must: write tests first (TDD), 
keep build warning-clean, commit with a clear message.

---

## Task 1 — MeetingBriefEngine: pre-meeting briefings

### What to build

When a calendar event starts in ≤15 minutes, Aria proactively composes and delivers 
a spoken context brief instead of just announcing the meeting title.

### Files

**New:** `Sources/Aria/Core/Proactive/MeetingBriefEngine.swift`  
**Modify:** `Sources/Aria/Core/Proactive/CalendarSignalProvider.swift`  
**Modify (lightly):** `Sources/Aria/Core/Proactive/ProactiveEngine.swift` (if wiring needed)  
**New test:** `Tests/AriaTests/MeetingBriefEngineTests.swift`  

### Spec

**`UpcomingEvent` struct** (already in CalendarSignalProvider.swift) — add optional `attendees: [String]` 
field (names/emails from EKEvent.attendees). Default `[]` so existing tests compile unchanged.

**`MeetingBriefEngine`** — a `Sendable` struct (not actor; it's stateless composition):

```swift
struct MeetingBriefEngine: Sendable {
    // Compose a meeting brief. Returns spoken text.
    // connectorsAvailable: list of connector IDs that are connected (to skip unavailable ones).
    func brief(
        for eventTitle: String,
        attendees: [String],
        connectorTools: MeetingConnectorTools,
        gemini: GeminiClient
    ) async -> String
}

// Injectable tool stubs for testing
struct MeetingConnectorTools: Sendable {
    var gmailRecent: @Sendable (String) async -> String    // query → results text
    var notionSearch: @Sendable (String) async -> String   // query → results text
    var driveSearch: @Sendable (String) async -> String    // query → results text
}
```

The `brief()` method:
1. Runs `gmailRecent`, `notionSearch`, `driveSearch` concurrently (async let) with the event title as query
2. Assembles a prompt: "You are Aria. Give a 3-sentence spoken meeting brief for '[title]' starting soon. Attendees: [names]. Recent Gmail: [snippet]. Notion: [snippet]. Drive: [snippet]. Be concise, spoken-word friendly."
3. Calls `gemini.generateText(prompt:)` → returns the spoken text
4. On any failure, falls back to: "Your [title] starts soon. [attendees joined]. Have a great meeting!"

**`CalendarSignalProvider`** changes:
- `leadWindow` default bumped from 300s → 900s (15 min) to give time to deliver the brief
- Suggestion `action` changes from `.acknowledge` to `.runCommand("brief me for: \(event.title)")` 
  for events with attendees, or `.acknowledge` if no attendees (no brief to compose)
- `spokenLine` changes to: `"You have \(event.title) in \(minutes) minutes. Want a briefing?"`

**Tests** (MeetingBriefEngineTests.swift):
- `testBriefWithAllConnectors` — inject stubs returning canned text; verify generated prompt contains title + attendees; mock gemini returns "Here is your brief" → verify returned
- `testBriefFallbackOnEmptyConnectors` — all stubs return ""; verify fallback text contains event title
- `testBriefFallbackOnGeminiError` — gemini throws; verify fallback returned (no crash)
- `testCalendarSignalWithAttendeesEmitsRunCommand` — attendees present → action == .runCommand
- `testCalendarSignalWithoutAttendeesEmitsAcknowledge` — no attendees → action == .acknowledge
- `testLeadWindowIs15Minutes` — verify leadWindow default == 900

Keep all existing CalendarSignalProviderTests passing (the new attendees field defaults to []).

### Commit message
`feat(proactive): MeetingBriefEngine — 15-min pre-meeting context brief`

---

## Task 2 — PlaybookRecorder: teach Aria new workflows by voice

### What to build

User can describe a workflow in plain English ("I want a recipe that checks my calendar, 
pulls recent Gmail, then searches Notion for current projects") and Aria converts it to 
a saved Recipe in RecipeStore. Also: list and delete recipes by voice.

### Files

**New:** `Sources/Aria/Core/Recipes/PlaybookRecorder.swift`  
**New:** `Sources/Aria/Tools/System/PlaybookTools.swift` — `recipe_teach`, `recipe_list`, `recipe_delete`  
**Modify:** `Sources/Aria/Tools/ToolRegistry.swift` — register new tools  
**New test:** `Tests/AriaTests/PlaybookRecorderTests.swift`  

### Spec

**`PlaybookRecorder`** actor:

```swift
actor PlaybookRecorder {
    static let shared: PlaybookRecorder

    // Parse a plain-English workflow description into RecipeSteps using Gemini,
    // then save to RecipeStore. Returns the saved Recipe.
    func teach(name: String, description: String, gemini: GeminiClient) async throws -> Recipe

    // List all saved recipes as a human-readable string
    func list() async -> String

    // Delete a recipe by name. Returns true if found+deleted.
    func delete(named: String) async -> Bool
}
```

`teach()` implementation:
1. Builds a prompt:
   ```
   Convert this workflow description into a JSON array of recipe steps.
   Available tools: [list the ToolRegistry catalog inline — just names + descriptions]
   
   Workflow name: "[name]"
   Description: "[description]"
   
   Output ONLY a JSON array, no markdown:
   [{"summary":"...", "tool":"...", "input":{"key":"value"}}, ...]
   
   Use only tools from the available list. If a step has no matching tool, skip it.
   ```
2. Calls `gemini.generateText(prompt:)` with temperature 0 (deterministic)
3. Parses JSON → `[RecipeStep]`
4. Creates `Recipe(name: name, steps: steps)` → `RecipeStore.shared.upsert(recipe)`
5. Returns the Recipe
6. On parse failure: throws `PlaybookError.parseFailure(raw: String)`

**New tools** (PlaybookTools.swift):

```swift
// recipe_teach: name + description → teaches Aria a new workflow
struct RecipeTeachTool: AriaTool {
    static let name = "recipe_teach"
    static let description = "Save a new workflow recipe. Input: name (recipe name), description (plain-English steps)."
    func run(input: [String: String]) async throws -> ToolResult
}

// recipe_list: → returns all saved recipes
struct RecipeListTool: AriaTool {
    static let name = "recipe_list"
    static let description = "List all saved workflow recipes. No input required."
    func run(input: [String: String]) async throws -> ToolResult
}

// recipe_delete: name → deletes a recipe
struct RecipeDeleteTool: AriaTool {
    static let name = "recipe_delete"
    static let description = "Delete a saved recipe by name. Input: name."
    func run(input: [String: String]) async throws -> ToolResult
}
```

Register all three in `ToolRegistry.builtins` array.

**Tests** (PlaybookRecorderTests.swift):
- `testTeachParsesStepsFromJSON` — inject gemini stub returning valid JSON; verify Recipe saved with correct steps
- `testTeachThrowsOnInvalidJSON` — stub returns garbage; verify throws `.parseFailure`
- `testListReturnsNames` — seed RecipeStore with 2 recipes; list() returns both names
- `testDeleteByName` — seed, delete by name, verify gone
- `testDeleteNonexistentReturnsFalse`
- `testRecipeTeachToolCallsRecorder` — tool.run() with name+description → recorder called

### Commit message
`feat(recipes): PlaybookRecorder — teach Aria new workflows by voice`

---

## Task 3 — GitHub + Linear connectors

### What to build

Two new data sources accessible via Aria tools:
- **GitHub**: list open issues and open PRs for a repo (Personal Access Token auth)
- **Linear**: list open issues and projects (API key auth)

Both are API-key based (simpler than OAuth — no OAuth2 flow needed). Keys live in Keychain.

### Files

**New:** `Sources/Aria/Core/Connectors/GitHubService.swift`  
**New:** `Sources/Aria/Core/Connectors/LinearService.swift`  
**New:** `Sources/Aria/Tools/Intelligence/GitHubTools.swift` — `github_issues`, `github_prs`  
**New:** `Sources/Aria/Tools/Intelligence/LinearTools.swift` — `linear_issues`, `linear_projects`  
**Modify:** `Sources/Aria/Tools/ToolRegistry.swift` — register new tools  
**New test:** `Tests/AriaTests/GitHubServiceTests.swift`  
**New test:** `Tests/AriaTests/LinearServiceTests.swift`  

### Spec

**`GitHubService`** struct (Sendable, no actor needed — pure HTTP):

```swift
struct GitHubService: Sendable {
    // Keychain account key for the PAT
    static let keychainAccount = "github_personal_access_token"

    var token: String  // injected; read from Keychain at call site

    // Returns open issues as formatted text. repo: "owner/repo"
    func issues(repo: String) async throws -> String

    // Returns open PRs as formatted text. repo: "owner/repo"
    func pullRequests(repo: String) async throws -> String
}
```

HTTP: `https://api.github.com/repos/{owner}/{repo}/issues?state=open&per_page=10`  
Headers: `Authorization: Bearer {token}`, `Accept: application/vnd.github+json`  
Parse: title + number + html_url + user.login for each item  
Format: "#{number} {title} by {user} — {url}" per line, max 10 items  
PRs: same endpoint with `?state=open&per_page=10&pulls=true` — actually use `/pulls` endpoint

**`LinearService`** struct (Sendable):

```swift
struct LinearService: Sendable {
    static let keychainAccount = "linear_api_key"
    var apiKey: String

    // Returns open issues as formatted text. teamId optional filter.
    func issues(teamId: String?) async throws -> String

    // Returns projects as formatted text.
    func projects() async throws -> String
}
```

Linear uses GraphQL: `POST https://api.linear.app/graphql`  
Headers: `Authorization: {apiKey}` (no "Bearer"), `Content-Type: application/json`  

Issues query:
```graphql
{ issues(filter: { state: { type: { eq: "started" } } }, first: 10) { nodes { title identifier url assignee { name } } } }
```
Projects query:
```graphql
{ projects(first: 10) { nodes { name description url } } }
```
Format similarly to GitHub.

**Tools** (GitHubTools.swift, LinearTools.swift):

```swift
struct GitHubIssuesTool: AriaTool {
    static let name = "github_issues"
    static let description = "List open GitHub issues for a repo. Input: repo (owner/repo format). Returns empty if no GitHub token configured."
    func run(input: [String: String]) async throws -> ToolResult
}

struct GitHubPRsTool: AriaTool {
    static let name = "github_prs"
    static let description = "List open GitHub pull requests for a repo. Input: repo (owner/repo format)."
    func run(input: [String: String]) async throws -> ToolResult
}

struct LinearIssuesTool: AriaTool {
    static let name = "linear_issues"
    static let description = "List open Linear issues. Optional input: teamId to filter by team."
    func run(input: [String: String]) async throws -> ToolResult
}

struct LinearProjectsTool: AriaTool {
    static let name = "linear_projects"
    static let description = "List Linear projects."
    func run(input: [String: String]) async throws -> ToolResult
}
```

Each tool: reads key from Keychain → if missing, returns `.ok("GitHub/Linear not configured. Add token in Settings → API Keys.")` instead of error. Register all 4 in `ToolRegistry.builtins`.

**Tests** — inject HTTP via a closure or protocol:
- `testGitHubIssuesFormatsCorrectly` — mock URLSession returning sample JSON; verify formatted output
- `testGitHubPRsFormatsCorrectly` — same for PRs endpoint
- `testGitHubMissingTokenReturnsGraceful` — no token → returns not-configured message
- `testLinearIssuesFormatsCorrectly` — mock GraphQL response
- `testLinearProjectsFormatsCorrectly`
- `testLinearMissingKeyReturnsGraceful`

For HTTP mocking: add a `urlSession: URLSession` injectable param to each service (default `.shared`), use a custom `URLProtocol` subclass in tests OR use a `fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)` closure injectable — whichever is cleaner for the codebase pattern.

### Commit message
`feat(connectors): GitHub + Linear tools (PAT + API key, no OAuth needed)`

---

## Task 4 — CrossConnectorSynthesizer: cross-app contextual intelligence

### What to build

When a user asks about a topic that spans multiple data sources ("What's happening with 
Project X?", "Give me everything about the Acme deal"), Aria gathers from all relevant 
connectors in parallel and synthesizes a unified answer.

Implementation: a new `cross_search` tool + `CrossConnectorSynthesizer` that runs 
multiple connector tools concurrently and synthesizes.

### Files

**New:** `Sources/Aria/Core/Intelligence/CrossConnectorSynthesizer.swift`  
**New:** `Sources/Aria/Tools/Intelligence/CrossSearchTool.swift`  
**Modify:** `Sources/Aria/Tools/ToolRegistry.swift` — register `cross_search`  
**New test:** `Tests/AriaTests/CrossConnectorSynthesizerTests.swift`  

### Spec

**`CrossConnectorSynthesizer`** struct (Sendable):

```swift
struct CrossConnectorSynthesizer: Sendable {
    struct Sources: Sendable {
        var gmail: @Sendable (String) async -> String
        var gcal: @Sendable (String) async -> String
        var notion: @Sendable (String) async -> String
        var drive: @Sendable (String) async -> String
        var slack: @Sendable (String) async -> String
        var github: @Sendable (String) async -> String    // empty if no token
        var linear: @Sendable (String) async -> String    // empty if no key
    }

    // Run all sources concurrently and synthesize. Returns spoken synthesis.
    func gather(topic: String, sources: Sources, gemini: GeminiClient) async -> String
}
```

`gather()` implementation:
1. Fire all 7 source closures concurrently with `async let`
2. Collect non-empty results with their source labels
3. If zero results: return `"I didn't find anything about '\(topic)' in your connected apps."`
4. Build synthesis prompt:
   ```
   Synthesize the following into a concise spoken summary about "[topic]".
   Each source is labeled. Be brief (3-5 sentences), spoken-word style, no markdown.
   
   [Gmail]: ...
   [Calendar]: ...
   [Notion]: ...
   ...
   ```
5. `gemini.generateText(prompt:)` → return result
6. On Gemini failure: concatenate the non-empty source snippets with source labels, return as-is

**`CrossSearchTool`**:

```swift
struct CrossSearchTool: AriaTool {
    static let name = "cross_search"
    static let description = "Search across ALL connected apps (Gmail, Calendar, Notion, Drive, Slack, GitHub, Linear) simultaneously and synthesize. Input: topic (what to look for)."
    func run(input: [String: String]) async throws -> ToolResult
}
```

The tool builds a `Sources` struct using live connector tokens (same pattern as 
GmailRecentTool reads token from ConnectorTokenStore) and calls `synthesizer.gather()`.

**Register** `cross_search` in `ToolRegistry.builtins`.

**Tests** (CrossConnectorSynthesizerTests.swift):
- `testGatherCombinesAllSources` — inject stubs all returning content; verify synthesis prompt contains all source labels
- `testGatherSkipsEmptySources` — 3 of 7 return ""; verify prompt only contains the 4 non-empty ones
- `testGatherReturnsNotFoundWhenAllEmpty` — all return ""; verify fallback "didn't find anything" message
- `testGatherFallbackOnGeminiError` — gemini throws; verify returns concatenated snippets (no crash)
- `testGatherRunsSourcesConcurrently` — use a counter + sleep stubs to verify all fire before any resolves (rough concurrency test)

### Commit message
`feat(intelligence): CrossConnectorSynthesizer + cross_search tool`

---

## Implementation order

1. Task 1 (MeetingBriefEngine) — most self-contained, touches only Proactive/
2. Task 2 (PlaybookRecorder) — touches Recipes/ + ToolRegistry
3. Task 3 (GitHub + Linear) — touches Connectors/ + ToolRegistry
4. Task 4 (CrossConnectorSynthesizer) — uses tools from Task 3, builds on connector pattern

## After all tasks

- Run full test suite: `swift test --package-path ~/Aria/.worktrees/aria-v12`
- `swift build -c release -Xswiftc -no-whole-module-optimization` — must be warning-clean
- Merge aria-v12 → main
