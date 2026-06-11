import Foundation
import AppKit

/// Coordinates one command end to end: capture screen → ask Gemini → persist the
/// turn → return a response for the UI. Tool execution is stubbed in the slice;
/// `action`/`multi_action` responses are recognized and reported as "not yet
/// wired up" so the protocol is exercised from day 1.
actor AgentOrchestrator {

    private let gemini: GeminiClient
    private let screen: ScreenCaptureEngine
    private let memory: ConversationMemory
    private let factory: DynamicToolFactory
    private let registry: ToolRegistry
    private let subAgents: SubAgentRegistry
    private let longTerm = LongTermMemory.shared

    /// Asks the user to approve running generated code. Param: a human-readable
    /// prompt (incl. code when "show code" is on). Returns true to proceed.
    /// When nil, destructive/confirmation-required runs are declined.
    var confirmationHandler: (@Sendable (String) async -> Bool)?

    init(gemini: GeminiClient = GeminiClient(),
         screen: ScreenCaptureEngine = ScreenCaptureEngine(),
         memory: ConversationMemory = ConversationMemory(),
         factory: DynamicToolFactory = DynamicToolFactory(),
         registry: ToolRegistry = ToolRegistry(),
         subAgents: SubAgentRegistry = SubAgentRegistry()) {
        self.gemini = gemini
        self.screen = screen
        self.memory = memory
        self.factory = factory
        self.registry = registry
        self.subAgents = subAgents
    }

    func setConfirmationHandler(_ handler: @escaping @Sendable (String) async -> Bool) {
        confirmationHandler = handler
    }

    /// The shared model client (briefing composer reuses its rotation/pacing).
    var geminiClient: GeminiClient { gemini }

    /// Plan-preview hook (V10): consulted before a foreground task executes its
    /// parsed plan. nil (and silent/background runs) = approve everything.
    var planApprovalHandler: (@Sendable ([TaskStep]) async -> Bool)?
    func setPlanApprovalHandler(_ handler: @escaping @Sendable ([TaskStep]) async -> Bool) {
        planApprovalHandler = handler
    }

    func handle(command: String, privacyMode: Bool = false) async -> AriaResponse {
        Log.agent.info("Handling command: \(command, privacy: .public)")

        if let local = localShortcut(for: command) {
            await record(command: command, response: local)
            return local
        }

        let screenshot: Data? = privacyMode ? nil : try? await screen.capturePrimaryJPEG()
        var history = await memory.recentContext()
        let context = await systemContext(privacyMode: privacyMode)
        let maxSteps = 4

        do {
            let catalog = await registry.catalog()
                + "\n\nSUB-AGENTS (dispatch via action tool = the agent name, input.task = the goal):\n"
                + (await subAgents.catalog())

            var transcript = command
            var turnScreenshot = screenshot
            var lastMessage = ""

            for step in 0..<maxSteps {
                Log.trace("orchestrator: step \(step) — sending to Gemini")
                let response = try await gemini.send(
                    transcript: transcript,
                    screenshotJPEG: turnScreenshot,
                    history: history,
                    context: context,
                    toolCatalog: catalog)
                lastMessage = response.message
                Log.trace("orchestrator: step \(step) type=\(response.type.rawValue) actions=\(response.actions.count)")

                switch response.type {
                case .answer, .clarify:
                    await record(command: command, response: response)
                    return response

                case .action, .multiAction:
                    var results = ""
                    var priorOutput = ""
                    for action in response.actions {
                        let r = await execute(action, priorOutput: priorOutput, context: context)
                        let line = r.success ? r.output : "FAILED: \(r.output)"
                        results += "\n- \(action.tool): \(line)"
                        Log.trace("orchestrator: step \(step) \(action.tool) success=\(r.success)")
                        priorOutput = r.output
                        if !r.success { break }
                    }
                    // Feed results back so the model decides the next step or the
                    // final spoken answer.
                    history.append(ConversationTurn(
                        transcript: transcript,
                        responseMessage: response.message,
                        responseType: response.type))
                    transcript = """
                    Results of the tool calls you just requested:\(results)

                    If the user's request is now complete, respond with type "answer" and a short, natural spoken message (no tool names or plumbing). If more steps are needed, respond with the next action(s).
                    """
                    turnScreenshot = nil
                }
            }

            let capped = AriaResponse(
                type: .answer,
                message: lastMessage.isEmpty ? "I wasn't able to finish that one." : lastMessage,
                confidence: 1.0)
            await record(command: command, response: capped)
            return capped

        } catch GeminiClient.GeminiError.missingAPIKey {
            return AriaResponse(type: .answer,
                message: "I don't have a Gemini API key yet. Add one in Settings.", confidence: 1.0)
        } catch {
            Log.agent.error("Gemini request failed: \(error.localizedDescription)")
            return AriaResponse(type: .answer,
                message: "Something went wrong reaching my brain. Try again in a moment.", confidence: 0.0)
        }
    }

    /// Run a single action. "dynamic" → factory codegen+exec. Other tools are
    /// routed to dynamic generation for now (static registry comes next pass).
    private func execute(_ action: AgentAction,
                         priorOutput: String,
                         context: GeminiClient.SystemContext) async -> ToolResult {
        // Sub-agent dispatch: tool name matches an agent, or tool == "agent".
        let agentName = action.tool == "agent" ? (action.input["name"] ?? "") : action.tool
        if let agent = await subAgents.agent(named: agentName) {
            let task = action.input["task"] ?? priorOutput
            let allowed = agent.allowedTools
            let ctx = AgentContext(
                gemini: gemini, registry: registry, factory: factory,
                system: context,
                runAction: { [weak self] act, prior in
                    // Hard scope: an agent may only run its declared tools.
                    guard SubAgentPolicy.permits(allowedTools: allowed, tool: act.tool) else {
                        let denied = ToolResult.fail("\(act.tool) isn't permitted for \(agentName).")
                        await ActivityLog.shared.record(
                            tool: act.tool, detail: "blocked: outside \(agentName) scope", result: denied)
                        return denied
                    }
                    return await self?.execute(act, priorOutput: prior, context: context)
                        ?? .fail("orchestrator gone")
                })
            let result = await agent.execute(task: task, context: ctx)
            return result.success ? .ok(result.output) : .fail(result.output)
        }

        // Native static tool wins if registered.
        if let tool = await registry.tool(named: action.tool) {
            // Universal safety gate: confirm anything destructive — whether the tool
            // declares itself destructive OR its name/input trips the Safety
            // heuristic (e.g. `shell` running `rm`, `applescript` that sends mail).
            // This covers EVERY caller — chat function-calls, the autonomy loop,
            // recovery/alternative actions, and agent-internal tool use — since they
            // all run through here.
            if tool.isDestructive || Safety.isDestructive(tool: action.tool, input: action.input) {
                let approved = await (confirmationHandler?(
                    "Run \(action.tool) with \(action.input)?") ?? false)
                guard approved else {
                    let declined = ToolResult.cancelled()
                    await ActivityLog.shared.record(tool: action.tool, detail: describe(action), result: declined)
                    return declined
                }
            }
            let result: ToolResult
            do { result = try await tool.run(input: action.input) }
            catch ToolError.missingInput(let key) { result = .fail("Missing input '\(key)' for \(action.tool).") }
            catch { result = .fail("\(action.tool) failed: \(error.localizedDescription)") }
            await ActivityLog.shared.record(tool: action.tool, detail: describe(action), result: result)
            return result
        }

        // Otherwise fall back to dynamic code generation.
        let settings = DynamicToolSettings.load()
        guard settings.allowCodeExecution else {
            return .fail("Code execution is disabled in settings.")
        }

        // Build the task: explicit dynamic task, else synthesize from tool+input.
        let language = ToolLanguage(rawValue: action.input["language"] ?? "python") ?? .python
        var task = action.input["task"] ?? describe(action)
        if !priorOutput.isEmpty {
            task += "\n\nPrevious step output to use as input:\n\(priorOutput)"
        }

        let tool: GeneratedTool
        do {
            tool = try await factory.generateTool(for: task, language: language, context: context)
        } catch {
            return .fail("Couldn't generate a tool: \(error.localizedDescription)")
        }

        // Confirmation gate: destructive intent or "show code before run".
        if Safety.isDestructive(summary: task) || settings.showCodeBeforeRun {
            let prompt = settings.showCodeBeforeRun
                ? "Aria wants to run this \(language.rawValue):\n\n\(tool.code)"
                : "This may modify or send data. Run it?"
            let approved = await (confirmationHandler?(prompt) ?? false)
            guard approved else {
                let declined = ToolResult.cancelled()
                await ActivityLog.shared.record(tool: action.tool, detail: describe(action), result: declined)
                return declined
            }
        }

        let result = await factory.execute(tool, timeout: 60)
        await ActivityLog.shared.record(tool: action.tool, detail: describe(action), result: result)

        // Offer to persist successful, non-trivial tools.
        if result.success, settings.askBeforeSaving,
           let confirm = confirmationHandler {
            let save = await confirm("That worked. Save '\(tool.name)' as a reusable tool?")
            if save { _ = await factory.saveTool(tool) }
        } else if result.success, !settings.askBeforeSaving {
            _ = await factory.saveTool(tool)
        }
        return result
    }

    private func describe(_ action: AgentAction) -> String {
        let inputs = action.input
            .filter { $0.key != "language" && $0.key != "task" }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        return inputs.isEmpty ? action.tool : "\(action.tool): \(inputs)"
    }

    /// Run a multi-step autonomous task. Emits `TaskEvent` values as each planning
    /// and execution step completes. Hooks into the same `execute` + `confirmationHandler`
    /// plumbing used by the normal command path.
    private func makeAutonomyEngine(silent: Bool = false) async -> AutonomyEngine {
        // currentSystemContext() is @MainActor, so we hop to it explicitly.
        let context = await MainActor.run { Self.currentSystemContext() }
        return AutonomyEngine(
            gemini: gemini,
            registry: registry,
            subAgents: subAgents,
            context: context,
            runAction: { [weak self] act, prior in
                await self?.execute(act, priorOutput: prior, context: context) ?? .fail("orchestrator gone")
            },
            confirm: { [weak self] prompt in
                await self?.confirmationHandler?(prompt) ?? false
            },
            approvePlan: { [weak self] steps in
                guard !silent, let handler = await self?.planApprovalHandler else { return true }
                return await handler(steps)
            })
    }

    /// An interrupted task waiting to be resumed, if any (its goal, for offering it).
    func pendingTask() async -> PersistedTask? { await TaskStore.shared.pending() }

    /// Resume the interrupted task from its persisted snapshot.
    func resumeTask(emit: @escaping @Sendable (TaskEvent) -> Void) async {
        guard let persisted = await TaskStore.shared.pending() else {
            emit(.finished(ok: false, summary: "There's no unfinished task to resume."))
            return
        }
        await makeAutonomyEngine().resume(persisted, emit: emit)
    }

    /// `silent: true` (background agents) skips the plan preview — nothing may
    /// speak or wait on the user from a background run.
    func runTask(goal: String, silent: Bool = false,
                 emit: @escaping @Sendable (TaskEvent) -> Void) async {
        await makeAutonomyEngine(silent: silent).run(goal: goal, emit: emit)
    }

    /// Streaming answer path (Phase 2: text + native function-calling loop).
    /// Calls `onText` with each text delta; runs up to maxRounds agentic turns.
    func handleStreaming(command: String, privacyMode: Bool,
                         onText: @escaping @Sendable (String) -> Void) async {
        // Cross-session memory: an explicit "remember that …" is saved deterministically
        // (zero model quota) and acknowledged.
        if let fact = MemoryCapture.extract(command) {
            await longTerm.remember(fact, kind: "fact")
            onText("Got it — I'll remember that.")
            await record(command: command, response: AriaResponse(type: .answer, message: "Got it — I'll remember that.", confidence: 1.0))
            return
        }

        // These five turn-setup reads are independent — run them concurrently so the
        // first model call waits on the slowest, not the sum (lower time-to-first-token).
        let wantsScreen = !privacyMode && ModelRouter.needsScreen(for: command)
        async let screenshotLoad: Data? = wantsScreen ? (try? await screen.capturePrimaryJPEG()) : nil
        async let historyLoad = memory.recentContext()
        async let contextLoad = systemContext(privacyMode: privacyMode, command: command)
        async let specsLoad = registry.specs()
        async let recalledLoad = longTerm.recall(for: command, limit: 4)   // relevant long-term facts

        Log.trace("turn: setup begin")
        let screenshot = await screenshotLoad;  Log.trace("turn: screenshot ok")
        var history = Array(await historyLoad.suffix(8)); Log.trace("turn: history ok")
        let context = await contextLoad;        Log.trace("turn: context ok")
        let specs = await specsLoad;            Log.trace("turn: specs ok")
        let recalled = await recalledLoad;      Log.trace("turn: recall ok")
        var transcript = command
        if !recalled.isEmpty {
            let known = recalled.map { "- \($0.text)" }.joined(separator: "\n")
            transcript = "(Relevant things you remember about me:\n\(known)\n)\n\n\(command)"
        }
        var turnScreenshot = screenshot
        var full = ""
        let maxRounds = 4
        do {
            for _ in 0..<maxRounds {
                var calls: [(name: String, args: [String: String])] = []
                Log.trace("turn: streaming…")
                let stream = await gemini.streamSend(transcript: transcript, screenshotJPEG: turnScreenshot,
                                                     history: history, context: context, toolCatalog: "", specs: specs,
                                                     preferredModel: ModelRouter.model(for: command))
                for try await ev in stream {
                    switch ev {
                    case .text(let t): full += t; onText(t)
                    case .functionCall(let name, let args): calls.append((name, args))
                    }
                }
                if calls.isEmpty { break }   // model is done talking/acting
                var results = ""
                let ctx = context
                await withTaskGroup(of: (String, ToolResult).self) { group in
                    for call in calls {
                        group.addTask {
                            let r = await self.execute(AgentAction(tool: call.name, input: call.args), priorOutput: "", context: ctx)
                            return (call.name, r)
                        }
                    }
                    for await (name, r) in group {
                        results += "\n\(name): \(r.success ? r.output : "FAILED: \(r.output)")"
                    }
                }
                history.append(ConversationTurn(transcript: transcript, responseMessage: full, responseType: .action))
                transcript = "Tool results:\(results)\n\nContinue: speak the final answer to the user, or call more tools if needed."
                turnScreenshot = nil
            }
        } catch {
            if case GeminiClient.GeminiError.http(429) = error {
                onText(" I've hit my free-tier limit for now — it resets after a bit. Try me again shortly.")
            } else {
                onText(" Sorry, I hit a problem reaching my brain.")
            }
        }
        await record(command: command, response: AriaResponse(type: .answer, message: full, confidence: 1.0))
    }

    // MARK: Local shortcuts

    private func localShortcut(for command: String) -> AriaResponse? {
        let c = command.lowercased()
        if c.contains("what did i ask") || c.contains("earlier") {
            return nil  // handled by Gemini with history context for now
        }
        return nil
    }

    // MARK: Persistence

    private func record(command: String, response: AriaResponse) async {
        await memory.append(ConversationTurn(
            transcript: command,
            responseMessage: response.message,
            responseType: response.type))
    }

    // MARK: System context

    @MainActor static func currentSystemContext() -> GeminiClient.SystemContext {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        return GeminiClient.SystemContext(currentApp: app, time: Date(), username: NSUserName())
    }

    /// Base system context plus ambient screen context. The AX read runs HERE, on the agent
    /// actor's executor (off the main thread) and time-bounded — so a slow Accessibility call
    /// can never freeze the main thread (which previously broke the whole turn: no reply, no
    /// voice, no re-arm, and a crash when Settings was opened afterward).
    func systemContext(privacyMode: Bool, command: String? = nil) async -> GeminiClient.SystemContext {
        var ctx = await MainActor.run { Self.currentSystemContext() }
        if !privacyMode, let pid = await MainActor.run(body: { AXReader.frontmostTarget()?.processIdentifier }) {
            let s = ScreenContext.snapshot(pid: pid)   // off-main, bounded
            ctx.windowTitle = s.windowTitle
            ctx.selection = s.selectedText
            ctx.focusedField = s.focusedRole
        }
        // Clipboard is attached only when the command refers to it — intentional, and
        // it keeps private clipboard data out of every other turn.
        if !privacyMode, let command, ContextRelevance.wantsClipboard(command) {
            let clip = await MainActor.run { NSPasteboard.general.string(forType: .string) ?? "" }
            ctx.clipboard = ScreenContext.cap(clip, 1000)
        }
        return ctx
    }
}
