import AppIntents
import Foundation

/// Makes Aria available as a macOS Shortcuts action.
/// Users can add "Run Aria Command" to any Shortcut.
struct RunAriaCommandIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Aria Command"
    static var description = IntentDescription("Send a command to Aria and get a response.")

    @Parameter(title: "Command", description: "What you want Aria to do")
    var command: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let controller = AriaController.shared else {
            return .result(value: "Aria is not running. Please open Aria and try again.")
        }
        let result = await controller.handleCommandForShortcuts(command)
        return .result(value: result)
    }
}

struct AriaShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunAriaCommandIntent(),
            phrases: ["Run \(.applicationName) command", "Ask \(.applicationName)"],
            shortTitle: "Run Command",
            systemImageName: "waveform"
        )
    }
}
