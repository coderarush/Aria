# Automation, Local Chat, and UI Recovery Design

## Goal

Stop unwanted background note creation, prevent tests from touching live Aria
data, restore reliable local conversation, and make the primary navigation and
command center appropriately clear and compact.

## Confirmed Causes

1. `AutomationCreateTool` and `AutomationListTool` are hard-wired to
   `AgentStore.shared`. `AutomationToolTests` therefore created agents in the
   real `~/Library/Application Support/Aria/agents.json` during every test run.
   The live file now contains more than 680 duplicate test automations, including
   Standup prep, Morning briefing, and Hourly check agents that create Apple Notes.
2. Background agents start unconditionally. There is no global user opt-in gate,
   so newly loaded or corrupted automations can execute immediately at launch.
3. Live chat defaults to `llama3.2:3b` when no separate chat model is configured.
   That model is not installed on this Mac. The configured and installed
   `qwen3:8b` model answers successfully through Ollama, but is never selected for
   live chat. The missing model fails before its first token, after which failing
   cloud credentials produce the generic brain error.
4. The command center is fixed at 620 points wide and may show eight recent rows.
   Its visual footprint is disproportionate to a short typed-command surface.
5. Main-window group headings exist, but 10-point tertiary text is too faint to
   reliably communicate Workspace, History, and Setup.

## Design

### Automation Isolation and Recovery

Both automation tools will accept an injected `AgentStore`, defaulting to
`.shared` in production. Tests will create a temporary store and pass it to both
tools, so test runs cannot write live agents.

`AgentStore` will sanitize persisted duplicate definitions during loading. When
multiple agents have the same normalized name, goal, and trigger, it will retain
one representative in a disabled state and discard the duplicates. The retained
entry will explain that it was paused because duplicate definitions were found.
Run history remains intact for auditability.

Background execution will gain a global `backgroundAgentsEnabled` preference
that defaults to false. `AgentCoordinator` will check this gate before sweeps and
watcher setup. Settings → Background Agents will show a prominent master toggle
and explain that no scheduled or watched automation runs while paused. Per-agent
toggles and definitions remain editable.

The existing polluted store will be cleaned by the load sanitizer when the fixed
app launches. The global pause prevents the remaining legitimate or unique agents
from running until the user deliberately enables them. Existing Apple Notes will
not be deleted automatically because deletion is irreversible.

### Local Conversation Routing

When `app.localChatModel` has no explicit value, `LocalFirstRouter` will use the
user's configured `app.localModelName`; only an empty planning selection falls
back to `OllamaProvider.defaultModel`. Runtime model caps remain family-aware and
will not substitute an unrelated missing Llama model for a configured Qwen model.

The router tests will verify this selection. A live Ollama check will confirm the
selected model produces a non-empty response before Aria is relaunched.

### Compact Command Center

A pure `CommandPaletteLayout` presentation type will define a 500-point width,
30-point rows, and at most four visible recent commands. The AppKit panel will use
that presentation for its frame and height. Keyboard navigation will operate on
the same visible recents, preserving Return, Escape, and arrow-key behavior.

### Clear Main Navigation

Each main-window group will gain a semantic SF Symbol and a stronger 11-point
secondary label. The sidebar will render the symbol and group title together,
while preserving every existing destination and eager SwiftUI hierarchy.

## Safety and Data Handling

- No Apple Notes are deleted automatically.
- Background agents remain paused until explicit opt-in.
- Duplicate recovery modifies only Aria's agent metadata and keeps run history.
- Tests use temporary files exclusively.
- No API keys, note bodies, or commands enter new presentation models.

## Verification

- Watch each new unit test fail before its production change.
- Run focused automation, coordinator, settings, local-router, palette, and main
  navigation tests after each isolated fix.
- Run the full suite and deterministic evaluation gate.
- Build and sign `.build/Aria.app`, verify its signature, and run `git diff --check`.
- Relaunch only after the live agent store is quarantined and background execution
  is confirmed paused.
