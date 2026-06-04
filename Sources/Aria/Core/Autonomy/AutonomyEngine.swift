import Foundation

/// Progress events emitted as the engine runs (drives the panel/status/voice).
enum TaskEvent: Sendable {
    case planReady(TaskPlan)
    case stepStarted(Int)
    case stepFinished(Int, ok: Bool, result: String)
    case narrate(String)
    case finished(ok: Bool, summary: String)
}

/// Runs a goal as Plan → Execute → (local) Verify → Recover, with a destructive
/// safety gate. Design goals (from live testing):
///   • Do it the first time — a reliable planner (proper text generation + a
///     can-do system framing + a worked example + an empty-plan retry).
///   • Pass results forward — each step sees the accumulated output of earlier
///     steps, so "research X and save a summary" actually has a summary to save.
///   • Never dead-end — a failed step is retried, then an alternative is tried,
///     then (for anything that's about recording text) the content is captured via
///     `save_note` so the user ALWAYS gets it; the task continues rather than
///     aborting on the first stumble.
/// All model calls go through the orchestrator's gemini (scheduler-paced), so the
/// whole thing stays free-tier safe.
actor AutonomyEngine {
    private let gemini: GeminiClient
    private let registry: ToolRegistry
    private let subAgents: SubAgentRegistry
    private let context: GeminiClient.SystemContext
    private let runAction: @Sendable (AgentAction, String) async -> ToolResult
    private let confirm: @Sendable (String) async -> Bool

    init(gemini: GeminiClient,
         registry: ToolRegistry,
         subAgents: SubAgentRegistry,
         context: GeminiClient.SystemContext,
         runAction: @escaping @Sendable (AgentAction, String) async -> ToolResult,
         confirm: @escaping @Sendable (String) async -> Bool) {
        self.gemini = gemini
        self.registry = registry
        self.subAgents = subAgents
        self.context = context
        self.runAction = runAction
        self.confirm = confirm
    }

    func run(goal: String, emit: @escaping @Sendable (TaskEvent) -> Void) async {
        let steps = await makePlan(goal: goal)
        guard !steps.isEmpty else {
            emit(.finished(ok: false, summary: "I couldn't work out how to do that one."))
            return
        }
        var plan = TaskPlan(goal: goal, steps: steps)
        emit(.planReady(plan))
        emit(.narrate("On it — " + plan.steps.map { $0.summary }.prefix(3).joined(separator: ", ") + "."))
        Log.trace("autonomy: plan has \(plan.steps.count) step(s) for '\(goal)'")

        var prior = ""   // accumulated output of completed steps, threaded forward
        for i in plan.steps.indices {
            if Task.isCancelled { return }   // Stop pressed — halt before the next step
            emit(.stepStarted(i))
            let step = plan.steps[i]
            Log.trace("autonomy: step \(i + 1)/\(plan.steps.count) — \(step.summary)")

            // Safety gate — destructive tool OR agent steps (verb is in the summary
            // for agents, in the tool/input for tools).
            let needsConfirm: Bool
            switch step.executor {
            case .tool(let t):  needsConfirm = Safety.isDestructive(tool: t, input: step.input)
            case .agent(let a): needsConfirm = Safety.isDestructive(tool: a, input: step.input)
                                    || Safety.isDestructive(summary: step.summary)
            }
            if needsConfirm {
                let okToRun = await confirm("Aria wants to \(step.summary). Allow?")
                if !okToRun {
                    plan.steps[i].status = .failed
                    plan.steps[i].result = "Skipped (not approved)."
                    emit(.stepFinished(i, ok: false, result: plan.steps[i].result))
                    continue
                }
            }

            var result = await execute(step, prior: prior)
            if !result.success { result = await execute(step, prior: prior) }   // verify: retry once
            if !result.success {
                result = await recover(step: step, prior: prior, goal: goal)   // never dead-end
            }

            plan.steps[i].status = result.success ? .done : .failed
            plan.steps[i].result = result.output
            emit(.stepFinished(i, ok: result.success, result: result.output))
            if result.success, !result.output.isEmpty { prior = result.output }
            // Note: we do NOT abort the whole task on a single failed step — we carry
            // on with the last good output so partial progress still reaches the user.
        }

        let done = plan.completedCount
        let summary: String
        if plan.isComplete {
            summary = "All done."
        } else if done > 0 {
            summary = "I finished \(done) of \(plan.total) steps; the rest I couldn't complete."
        } else {
            summary = "I wasn't able to complete that one."
        }
        emit(.finished(ok: done > 0, summary: summary))
    }

    // MARK: Planning

    private func makePlan(goal: String) async -> [TaskStep] {
        let prompt = await planPrompt(goal: goal)
        for attempt in 0..<2 {
            let p = attempt == 0 ? prompt
                : prompt + "\n\nReminder: output ONLY the raw JSON array — no prose, no code fences."
            let raw = (try? await gemini.generateText(prompt: p, temperature: 0.2)) ?? ""
            let steps = PlanParser.steps(fromJSON: raw)
            if !steps.isEmpty { return steps }
            Log.trace("autonomy: empty plan (attempt \(attempt + 1)); retrying")
        }
        // Last resort: never dead-end on planning — hand the whole goal to Atlas, who
        // breaks it down and operates the Mac directly.
        Log.trace("autonomy: falling back to a single Atlas step")
        return [TaskStep(summary: goal, executor: .agent("Atlas"))]
    }

    private func planPrompt(goal: String) async -> String {
        let catalog = await registry.catalog()
        let crew = await subAgents.crew()
            .map { "- \($0.name): \($0.description)" }
            .joined(separator: "\n")
        return """
        You are Aria, an autonomous agent that fully controls this Mac. Through these \
        tools — especially `shell` and `applescript` — you can operate ANY app, file, or \
        system setting. You can ALWAYS accomplish the goal: never refuse, never say you \
        can't, never leave it half-done. To record or save text for the user, use \
        `save_note` (it lands in Apple Notes, or falls back to a file + clipboard).

        Break the goal into an ordered JSON array of steps. Each step is:
        {"summary": "short human text", "agent": "<crew member>" OR "tool": "<tool name>", "input": {...}}
        Use a crew member for research/writing/code; use a tool for concrete actions. \
        A later step automatically receives the previous steps' output as its material — \
        so for a save/write step you can leave the content field empty and it will be \
        filled from the earlier result. Output ONLY the JSON array.

        EXAMPLE
        GOAL: research the best usb mics and save a summary to a note
        [{"summary":"Research the best USB mics","agent":"Orion","input":{"query":"best USB microphones"}},
         {"summary":"Save the summary to a note","tool":"save_note","input":{"title":"Best USB Mics"}}]

        CREW:
        \(crew)

        TOOLS:
        \(catalog)

        GOAL: \(goal)
        """
    }

    // MARK: Execution

    private func execute(_ step: TaskStep, prior: String) async -> ToolResult {
        switch step.executor {
        case .tool(let name):
            let input = enrich(input: step.input, forTool: name, prior: prior)
            return await runAction(AgentAction(tool: name, input: input), prior)

        case .agent(let agentName):
            guard let agent = await subAgents.agent(named: agentName) else {
                return .fail("No crew member named \(agentName).")
            }
            let ctx = AgentContext(
                gemini: gemini, registry: registry, factory: DynamicToolFactory(),
                system: context, runAction: runAction)
            var taskText = step.summary
            let extra = step.input.values.joined(separator: " ")
            if !extra.isEmpty { taskText += " " + extra }
            if !prior.isEmpty {
                taskText += "\n\nMaterial from earlier steps (use this):\n" + String(prior.prefix(6000))
            }
            let r = await agent.execute(task: taskText, context: ctx)
            return r.success ? .ok(r.output) : .fail(r.output)
        }
    }

    /// Fill a write/save tool's content field from the prior step's output when the
    /// planner left it empty (the summary doesn't exist until the earlier step ran).
    private func enrich(input: [String: String], forTool name: String, prior: String) -> [String: String] {
        guard !prior.isEmpty else { return input }
        var out = input
        func fillIfEmpty(_ key: String) { if (out[key]?.isEmpty ?? true) { out[key] = prior } }
        switch name {
        case "save_note":  fillIfEmpty("content")
        case "file_write": fillIfEmpty("content")
        case "clipboard":  if (out["action"] ?? "write") == "write" { fillIfEmpty("text") }
        default: break
        }
        return out
    }

    // MARK: Recovery (never dead-end)

    private func recover(step: TaskStep, prior: String, goal: String) async -> ToolResult {
        Log.trace("autonomy: recovering failed step '\(step.summary)'")

        // If this step is about recording/saving text, guarantee the user gets it.
        if Self.isSaveIntent(step.summary) || isWriteTool(step.executor) {
            let content = prior.isEmpty ? step.summary : prior
            let title = Self.titleFromGoal(goal)
            let r = await runAction(
                AgentAction(tool: "save_note", input: ["title": title, "content": content]), "")
            if r.success { return r }
        }

        // Otherwise ask the model for one alternative action and try it.
        if let alt = await alternativeAction(for: step, prior: prior) {
            let r = await runAction(alt, prior)
            if r.success { return r }
        }

        return .fail("Couldn't complete: \(step.summary)")
    }

    private func alternativeAction(for step: TaskStep, prior: String) async -> AgentAction? {
        let catalog = await registry.catalog()
        let prompt = """
        A step failed. Propose ONE alternative tool action that accomplishes it, as a \
        single JSON object: {"tool":"<name>","input":{...}}. Prefer `shell` or \
        `applescript` if nothing else fits — you can always find a way on a Mac. \
        Output ONLY the JSON object.

        STEP: \(step.summary)
        MATERIAL (from earlier steps, may be what to act on):
        \(String(prior.prefix(2000)))

        TOOLS:
        \(catalog)
        """
        let raw = (try? await gemini.generateText(prompt: prompt, temperature: 0.2)) ?? ""
        let cleaned = GeminiClient.stripCodeFences(raw)
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}"),
              let data = String(cleaned[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = obj["tool"] as? String, !tool.isEmpty
        else { return nil }
        let input = (obj["input"] as? [String: Any])?.reduce(into: [String: String]()) {
            $0[$1.key] = String(describing: $1.value)
        } ?? [:]
        return AgentAction(tool: tool, input: input)
    }

    private func isWriteTool(_ e: StepExecutor) -> Bool {
        if case .tool(let t) = e { return ["save_note", "file_write", "clipboard"].contains(t) }
        return false
    }

    // MARK: Save-intent heuristics (also reused by tests)

    private static let saveWords = ["note", "save", "write down", "write it down", "jot",
                                    "record", "remember", "summary to", "to a note",
                                    "in notes", "to notes", "take down"]

    static func isSaveIntent(_ summary: String) -> Bool {
        let l = summary.lowercased()
        return saveWords.contains { l.contains($0) }
    }

    static func titleFromGoal(_ goal: String) -> String {
        let words = goal.split(separator: " ").prefix(8).joined(separator: " ")
        return words.isEmpty ? "Aria Note" : words.prefix(1).uppercased() + words.dropFirst()
    }
}
