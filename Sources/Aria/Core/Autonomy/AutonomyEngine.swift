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
/// safety gate. All model calls go through the orchestrator's gemini (scheduler-
/// paced), so the whole thing is free-tier safe.
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
        let catalog = await registry.catalog()
        // crew() returns [(name, persona, description)]
        let crew = await subAgents.crew()
            .map { "- \($0.name): \($0.description)" }
            .joined(separator: "\n")

        let planPrompt = """
        Break this goal into an ordered JSON array of steps. Each step: \
        {"summary": short text, "agent": one of the crew OR "tool": a tool name, "input": {...}}. \
        Prefer deterministic tools for concrete actions; use a crew member for research/writing/code. \
        Output ONLY the JSON array.

        GOAL: \(goal)

        CREW:
        \(crew)

        TOOLS:
        \(catalog)
        """

        let raw = (try? await gemini.generateScript(
            task: "print this JSON array and nothing else: \(planPrompt)",
            language: .bash,
            context: context)) ?? ""

        var plan = TaskPlan(goal: goal, steps: PlanParser.steps(fromJSON: raw))
        guard !plan.steps.isEmpty else {
            emit(.finished(ok: false, summary: "I couldn't work out a plan for that."))
            return
        }

        emit(.planReady(plan))
        emit(.narrate("Here's my plan — "
            + plan.steps.map { $0.summary }.prefix(3).joined(separator: ", ") + "."))

        for i in plan.steps.indices {
            if Task.isCancelled { return }   // Stop pressed — halt before the next step
            emit(.stepStarted(i))
            let step = plan.steps[i]

            // Safety gate — destructive tool steps AND destructive agent steps (the
            // danger verb is in the tool/input for tools, in the summary for agents,
            // e.g. Comet "send the email", Atlas "delete the backups").
            let needsConfirm: Bool
            switch step.executor {
            case .tool(let t):
                needsConfirm = Safety.isDestructive(tool: t, input: step.input)
            case .agent(let a):
                needsConfirm = Safety.isDestructive(tool: a, input: step.input)
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

            var result = await execute(step)
            if !result.success { result = await execute(step) }   // local verify: retry once

            plan.steps[i].status = result.success ? .done : .failed
            plan.steps[i].result = result.output
            emit(.stepFinished(i, ok: result.success, result: result.output))

            if !result.success {
                emit(.finished(ok: false, summary: "Step \(i + 1) failed: \(result.output.prefix(120))"))
                return
            }
        }

        emit(.finished(ok: true, summary: "All done."))
    }

    private func execute(_ step: TaskStep) async -> ToolResult {
        switch step.executor {
        case .tool(let name):
            return await runAction(AgentAction(tool: name, input: step.input), "")

        case .agent(let agentName):
            guard let agent = await subAgents.agent(named: agentName) else {
                return .fail("No crew member named \(agentName).")
            }
            let ctx = AgentContext(
                gemini: gemini,
                registry: registry,
                factory: DynamicToolFactory(),
                system: context,
                runAction: runAction)
            let taskText = step.summary + " " + step.input.values.joined(separator: " ")
            let r = await agent.execute(task: taskText, context: ctx)
            return r.success ? .ok(r.output) : .fail(r.output)
        }
    }
}
