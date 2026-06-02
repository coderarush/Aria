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

    /// Asks the user to approve running generated code. Param: a human-readable
    /// prompt (incl. code when "show code" is on). Returns true to proceed.
    /// When nil, destructive/confirmation-required runs are declined.
    var confirmationHandler: (@Sendable (String) async -> Bool)?

    init(gemini: GeminiClient = GeminiClient(),
         screen: ScreenCaptureEngine = ScreenCaptureEngine(),
         memory: ConversationMemory = ConversationMemory(),
         factory: DynamicToolFactory = DynamicToolFactory()) {
        self.gemini = gemini
        self.screen = screen
        self.memory = memory
        self.factory = factory
    }

    func setConfirmationHandler(_ handler: @escaping @Sendable (String) async -> Bool) {
        confirmationHandler = handler
    }

    /// Process a spoken command and return what to display.
    func handle(command: String, privacyMode: Bool = false) async -> FridayResponse {
        Log.agent.info("Handling command: \(command, privacy: .public)")

        // Local fast-paths that don't need the model.
        if let local = localShortcut(for: command) {
            await record(command: command, response: local)
            return local
        }

        let screenshot: Data? = privacyMode ? nil : try? await screen.capturePrimaryJPEG()
        let history = await memory.recentContext()
        let context = await Self.currentSystemContext()

        do {
            let response = try await gemini.send(
                transcript: command,
                screenshotJPEG: screenshot,
                history: history,
                context: context)

            let final = await routeActions(response, context: context)
            await record(command: command, response: final)
            return final
        } catch GeminiClient.GeminiError.missingAPIKey {
            return FridayResponse(type: .answer,
                message: "I don't have a Gemini API key yet. Add one in Settings.",
                confidence: 1.0)
        } catch {
            Log.agent.error("Gemini request failed: \(error.localizedDescription)")
            return FridayResponse(type: .answer,
                message: "Something went wrong reaching my brain. Try again in a moment.",
                confidence: 0.0)
        }
    }

    // MARK: Action routing

    /// Execute the actions Gemini requested. Each step's output feeds the next
    /// step's context (sequential pipeline). Unknown tools fall back to dynamic
    /// code generation. Static tools land in a later pass.
    private func routeActions(_ response: FridayResponse,
                              context: GeminiClient.SystemContext) async -> FridayResponse {
        switch response.type {
        case .answer, .clarify:
            return response
        case .action, .multiAction:
            var transcript = response.message
            var priorOutput = ""
            for action in response.actions {
                let result = await execute(action, priorOutput: priorOutput, context: context)
                transcript += "\n\n**\(action.tool)** → \(result.output)"
                priorOutput = result.output
                if !result.success { break }
            }
            return FridayResponse(
                type: .answer,
                message: transcript,
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
                ? "Friday wants to run this \(language.rawValue):\n\n\(tool.code)"
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

    private func localShortcut(for command: String) -> FridayResponse? {
        let c = command.lowercased()
        if c.contains("what did i ask") || c.contains("earlier") {
            return nil  // handled by Gemini with history context for now
        }
        return nil
    }

    // MARK: Persistence

    private func record(command: String, response: FridayResponse) async {
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
