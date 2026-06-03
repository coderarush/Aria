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

    func handle(command: String, privacyMode: Bool = false) async -> AriaResponse {
        Log.agent.info("Handling command: \(command, privacy: .public)")

        if let local = localShortcut(for: command) {
            await record(command: command, response: local)
            return local
        }

        let screenshot: Data? = privacyMode ? nil : try? await screen.capturePrimaryJPEG()
        var history = await memory.recentContext()
        let context = await Self.currentSystemContext()
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
            let ctx = AgentContext(
                gemini: gemini, registry: registry, factory: factory,
                system: context,
                runAction: { [weak self] act, prior in
                    await self?.execute(act, priorOutput: prior, context: context)
                        ?? .fail("orchestrator gone")
                })
            let result = await agent.execute(task: task, context: ctx)
            return result.success ? .ok(result.output) : .fail(result.output)
        }

        // Native static tool wins if registered.
        if let tool = await registry.tool(named: action.tool) {
            if tool.isDestructive {
                let approved = await (confirmationHandler?(
                    "Run \(action.tool) with \(action.input)?") ?? false)
                guard approved else { return .fail("Cancelled — not approved.") }
            }
            do { return try await tool.run(input: action.input) }
            catch ToolError.missingInput(let key) { return .fail("Missing input '\(key)' for \(action.tool).") }
            catch { return .fail("\(action.tool) failed: \(error.localizedDescription)") }
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
        if isDestructive(task) || settings.showCodeBeforeRun {
            let prompt = settings.showCodeBeforeRun
                ? "Aria wants to run this \(language.rawValue):\n\n\(tool.code)"
                : "This may modify or send data. Run it?"
            let approved = await (confirmationHandler?(prompt) ?? false)
            guard approved else { return .fail("Cancelled — not approved.") }
        }

        let result = await factory.execute(tool, timeout: 60)

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

    private func isDestructive(_ task: String) -> Bool {
        let t = task.lowercased()
        return ["delete", "remove", "rm ", "send", "post", "email", "submit",
                "overwrite", "drop ", "kill"].contains { t.contains($0) }
    }

    /// Streaming answer path (Phase 1: text only; tools come in Phase 2).
    /// Calls `onText` with each text delta; returns when the stream ends.
    func handleStreaming(command: String, privacyMode: Bool,
                         onText: @escaping @Sendable (String) -> Void) async {
        let screenshot: Data? = privacyMode ? nil : try? await screen.capturePrimaryJPEG()
        let history = await memory.recentContext()
        let context = await Self.currentSystemContext()
        let catalog = await registry.catalog()
        var full = ""
        do {
            let stream = await gemini.streamSend(transcript: command, screenshotJPEG: screenshot,
                                                  history: history, context: context, toolCatalog: catalog)
            for try await ev in stream {
                if case let .text(t) = ev { full += t; onText(t) }
            }
        } catch {
            onText("Something went wrong reaching my brain.")
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

    @MainActor
    static func currentSystemContext() -> GeminiClient.SystemContext {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        return GeminiClient.SystemContext(
            currentApp: app,
            time: Date(),
            username: NSUserName())
    }
}
