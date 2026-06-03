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

    /// Process a spoken command and return what to display.
    func handle(command: String, privacyMode: Bool = false) async -> AriaResponse {
        Log.agent.info("Handling command: \(command, privacy: .public)")

        // Local fast-paths that don't need the model.
        if let local = localShortcut(for: command) {
            await record(command: command, response: local)
            return local
        }

        Log.trace("orchestrator: capturing screen (privacy=\(privacyMode))")
        let screenshot: Data? = privacyMode ? nil : try? await screen.capturePrimaryJPEG()
        Log.trace("orchestrator: screenshot=\(screenshot?.count ?? -1) bytes; building catalog")
        let history = await memory.recentContext()
        let context = await Self.currentSystemContext()

        do {
            let catalog = await registry.catalog()
                + "\n\nSUB-AGENTS (dispatch via action tool = the agent name, input.task = the goal):\n"
                + (await subAgents.catalog())
            Log.trace("orchestrator: sending to Gemini")
            let response = try await gemini.send(
                transcript: command,
                screenshotJPEG: screenshot,
                history: history,
                context: context,
                toolCatalog: catalog)
            Log.trace("orchestrator: Gemini ok, type=\(response.type.rawValue) actions=\(response.actions.count)")

            let final = await routeActions(response, context: context)
            Log.trace("orchestrator: routeActions done")
            await record(command: command, response: final)
            return final
        } catch GeminiClient.GeminiError.missingAPIKey {
            Log.trace("orchestrator: MISSING API KEY")
            return AriaResponse(type: .answer,
                message: "I don't have a Gemini API key yet. Add one in Settings.",
                confidence: 1.0)
        } catch {
            Log.trace("orchestrator: Gemini FAILED: \(error)")
            Log.agent.error("Gemini request failed: \(error.localizedDescription)")
            return AriaResponse(type: .answer,
                message: "Something went wrong: \(error.localizedDescription)",
                confidence: 0.0)
        }
    }

    // MARK: Action routing

    /// Execute the actions Gemini requested. Each step's output feeds the next
    /// step's context (sequential pipeline). Unknown tools fall back to dynamic
    /// code generation. Static tools land in a later pass.
    private func routeActions(_ response: AriaResponse,
                              context: GeminiClient.SystemContext) async -> AriaResponse {
        switch response.type {
        case .answer, .clarify:
            return response
        case .action, .multiAction:
            var priorOutput = ""
            var failure: String? = nil
            for action in response.actions {
                let result = await execute(action, priorOutput: priorOutput, context: context)
                // Tool plumbing stays in the log, never in what Aria shows/speaks.
                Log.trace("orchestrator: tool \(action.tool) success=\(result.success) → \(result.output)")
                priorOutput = result.output
                if !result.success { failure = result.output; break }
            }
            // The user hears only Aria's natural reply. On failure, say so plainly
            // (graceful, not silent) instead of pretending it worked.
            if let failure {
                return AriaResponse(
                    type: .answer,
                    message: "\(response.message)… actually, that didn't go through: \(failure)",
                    confidence: 0.0,
                    actions: response.actions,
                    followup: response.followup)
            }
            return AriaResponse(
                type: .answer,
                message: response.message,
                confidence: response.confidence,
                actions: response.actions,
                followup: response.followup)
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
