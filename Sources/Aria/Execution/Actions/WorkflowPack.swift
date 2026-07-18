import Foundation

/// V11 P17 — a persona bundle: recipes + background agents installed together.
/// Architecture only (no marketplace): built-ins ship in code, and the same
/// shape serializes to JSON for future sharing.
struct WorkflowPack: Codable, Equatable, Sendable, Identifiable {
    /// Stable key ("founder") — recipes installed by a pack carry it.
    let key: String
    let persona: String
    let summary: String
    var recipes: [Recipe]
    /// (name, goal, trigger) triples for background agents the pack suggests.
    var agents: [BackgroundAgent]

    var id: String { key }

    // MARK: built-ins

    static let builtins: [WorkflowPack] = [founder, student, developer, creator, aiBuilder]

    /// Pack for a persona name ("Student" → student pack); nil for unknown.
    static func forPersona(_ persona: String) -> WorkflowPack? {
        builtins.first { $0.persona.lowercased() == persona.lowercased() }
    }

    static let founder = WorkflowPack(
        key: "founder",
        persona: "Founder",
        summary: "Briefings, meeting prep, research — stay ahead of the day.",
        recipes: [
            Recipe(name: "Morning startup", steps: [
                RecipeStep(summary: "Open Calendar", tool: "open_app", input: ["name": "Calendar"]),
                RecipeStep(summary: "Open Mail", tool: "open_app", input: ["name": "Mail"]),
                RecipeStep(summary: "Compose the daily briefing", tool: "daily_briefing")
            ], packKey: "founder"),
            Recipe(name: "Meeting prep", steps: [
                RecipeStep(summary: "Today's calendar", tool: "calendar", input: ["range": "today"]),
                RecipeStep(summary: "Recent matching notes", tool: "notes_read", input: ["query": "meeting"]),
                RecipeStep(summary: "Recent project work", tool: "recall_work", input: ["timeframe": "this week"])
            ], packKey: "founder"),
            Recipe(name: "Wind down", steps: [
                RecipeStep(summary: "Today's timeline", tool: "timeline", input: ["timeframe": "today"]),
                RecipeStep(summary: "Save the recap as a note", tool: "save_note",
                           input: ["title": "Daily recap"])
            ], packKey: "founder")
        ],
        agents: [
            BackgroundAgent(name: "Daily briefing",
                            goal: BriefingComposer.agentSentinel,
                            trigger: .daily(hour: 8, minute: 30))
        ])

    static let student = WorkflowPack(
        key: "student",
        persona: "Student",
        summary: "Study sessions, assignment tracking, exam prep.",
        recipes: [
            Recipe(name: "Study session", steps: [
                RecipeStep(summary: "Open Notes", tool: "open_app", input: ["name": "Notes"]),
                RecipeStep(summary: "Open Calendar", tool: "open_app", input: ["name": "Calendar"]),
                RecipeStep(summary: "What's due", tool: "calendar", input: ["range": "week"])
            ], packKey: "student"),
            Recipe(name: "Assignment check", steps: [
                RecipeStep(summary: "Reminders due", tool: "reminders", input: ["filter": "due"]),
                RecipeStep(summary: "Recent class notes", tool: "notes_read", input: ["query": "class"])
            ], packKey: "student"),
            Recipe(name: "Wrap up studying", steps: [
                RecipeStep(summary: "Today's timeline", tool: "timeline", input: ["timeframe": "today"]),
                RecipeStep(summary: "Save a study log", tool: "save_note",
                           input: ["title": "Study log"])
            ], packKey: "student")
        ],
        agents: [
            BackgroundAgent(name: "Daily briefing",
                            goal: BriefingComposer.agentSentinel,
                            trigger: .daily(hour: 7, minute: 45))
        ])

    static let developer = WorkflowPack(
        key: "developer",
        persona: "Developer",
        summary: "Project resume, daily standup prep, focused work.",
        recipes: [
            Recipe(name: "Dev startup", steps: [
                RecipeStep(summary: "Open the editor", tool: "open_app", input: ["name": "Visual Studio Code"]),
                RecipeStep(summary: "Open Terminal", tool: "open_app", input: ["name": "Terminal"]),
                RecipeStep(summary: "Where I left off", tool: "recall_work", input: ["timeframe": "yesterday"])
            ], packKey: "developer"),
            Recipe(name: "Standup prep", steps: [
                RecipeStep(summary: "Yesterday's work", tool: "recall_work", input: ["timeframe": "yesterday"]),
                RecipeStep(summary: "Today's calendar", tool: "calendar", input: ["range": "today"])
            ], packKey: "developer"),
            Recipe(name: "End of day", steps: [
                RecipeStep(summary: "Today's timeline", tool: "timeline", input: ["timeframe": "today"]),
                RecipeStep(summary: "Save the work log", tool: "save_note",
                           input: ["title": "Work log"])
            ], packKey: "developer")
        ],
        agents: [
            BackgroundAgent(name: "Daily briefing",
                            goal: BriefingComposer.agentSentinel,
                            trigger: .daily(hour: 9, minute: 0))
        ])

    static let creator = WorkflowPack(
        key: "creator",
        persona: "Creator",
        summary: "Turn ideas into publishable drafts, launch assets, and follow-up loops.",
        recipes: [
            Recipe(name: "Content launch", steps: [
                RecipeStep(summary: "Collect recent notes", tool: "notes_read", input: ["query": "idea"]),
                RecipeStep(summary: "Research the topic", tool: "research", input: ["query": "topic"]),
                RecipeStep(summary: "Improve the draft", tool: "draft_feedback", input: ["goal": "make this clearer and more compelling"])
            ], packKey: "creator"),
            Recipe(name: "Audience follow-up", steps: [
                RecipeStep(summary: "Find recent email", tool: "gmail_recent", input: ["limit": "10"]),
                RecipeStep(summary: "Suggest replies", tool: "smart_reply", input: ["tone": "warm concise"]),
                RecipeStep(summary: "Check follow-ups", tool: "followup_check", input: [:])
            ], packKey: "creator"),
            Recipe(name: "Creative wrap", steps: [
                RecipeStep(summary: "Today’s timeline", tool: "timeline", input: ["timeframe": "today"]),
                RecipeStep(summary: "Save what shipped", tool: "save_note", input: ["title": "Creative log"])
            ], packKey: "creator")
        ],
        agents: [
            BackgroundAgent(name: "Creator daily sweep",
                            goal: BriefingComposer.agentSentinel,
                            trigger: .daily(hour: 10, minute: 0))
        ])

    static let aiBuilder = WorkflowPack(
        key: "ai_builder",
        persona: "AI Builder",
        summary: "Audit, build, test, and ship assistant features without losing product context.",
        recipes: [
            Recipe(name: "Assistant build loop", steps: [
                RecipeStep(summary: "Recover current project status", tool: "status", input: ["project": "Aria"]),
                RecipeStep(summary: "Recall recent implementation work", tool: "recall_work", input: ["timeframe": "this week"]),
                RecipeStep(summary: "List saved workflows", tool: "recipe_list", input: [:])
            ], packKey: "ai_builder"),
            Recipe(name: "Assistant audit", steps: [
                RecipeStep(summary: "Review open loops", tool: "status", input: ["project": "Aria"]),
                RecipeStep(summary: "Check assistant capability gaps", tool: "assistant_benchmark", input: ["focus": "Aria"]),
                RecipeStep(summary: "Save audit notes", tool: "save_note", input: ["title": "Aria audit"])
            ], packKey: "ai_builder"),
            Recipe(name: "Ship readiness", steps: [
                RecipeStep(summary: "Review today’s timeline", tool: "timeline", input: ["timeframe": "today"]),
                RecipeStep(summary: "Summarize recent work", tool: "recall_work", input: ["timeframe": "today"]),
                RecipeStep(summary: "Prepare daily review", tool: "daily_review", input: [:])
            ], packKey: "ai_builder")
        ],
        agents: [
            BackgroundAgent(name: "Assistant build briefing",
                            goal: BriefingComposer.agentSentinel,
                            trigger: .daily(hour: 9, minute: 15))
        ])
}

/// Installs a pack: upserts its recipes and agents by NAME (never duplicates;
/// a re-install refreshes pack-owned items and leaves user items alone).
enum PackInstaller {
    static func install(_ pack: WorkflowPack,
                        recipes: RecipeStore = .shared,
                        agents: AgentStore = .shared) async {
        for recipe in pack.recipes {
            if let existing = await recipes.named(recipe.name) {
                guard existing.packKey == pack.key else { continue }   // user owns the name
                var updated = recipe
                updated = Recipe(id: existing.id, name: recipe.name,
                                 steps: recipe.steps, packKey: pack.key)
                await recipes.upsert(updated)
            } else {
                await recipes.upsert(recipe)
            }
        }
        let existingAgents = await agents.all()
        for agent in pack.agents where !existingAgents.contains(where: { $0.name == agent.name }) {
            await agents.upsert(agent)
        }
    }
}
