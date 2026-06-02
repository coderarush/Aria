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

    init(gemini: GeminiClient = GeminiClient(),
         screen: ScreenCaptureEngine = ScreenCaptureEngine(),
         memory: ConversationMemory = ConversationMemory()) {
        self.gemini = gemini
        self.screen = screen
        self.memory = memory
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
            var response = try await gemini.send(
                transcript: command,
                screenshotJPEG: screenshot,
                history: history,
                context: context)

            response = routeActions(response)
            await record(command: command, response: response)
            return response
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

    // MARK: Action routing (stubbed in slice)

    private func routeActions(_ response: FridayResponse) -> FridayResponse {
        switch response.type {
        case .answer, .clarify:
            return response
        case .action, .multiAction:
            let names = response.actions.map(\.tool).joined(separator: ", ")
            Log.agent.info("Action(s) requested but not yet implemented: \(names)")
            return FridayResponse(
                type: .answer,
                message: response.message + "\n\n_(Actions [\(names)] aren't wired up yet — coming in the next build.)_",
                confidence: response.confidence,
                actions: response.actions,
                followup: response.followup)
        }
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
