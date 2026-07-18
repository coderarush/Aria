import Foundation

/// Start recording UI actions into a named recipe.
struct UIRecordStartTool: AriaTool {
    static let name = "ui_record_start"
    static let description = "Start recording UI actions into a recipe. Input: name (recipe name to save as)."
    static let paramHints: [String: String] = [
        "name": "The name to save the recipe as"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let name = input["name"], !name.isEmpty else {
            return .fail("Missing input: name")
        }
        await UIRecorder.shared.startRecording(name: name)
        return .ok("Recording started. Perform actions in any app — Aria will capture them. Say 'stop recording' when done.")
    }
}

/// Stop recording and save the captured actions as a recipe.
struct UIRecordStopTool: AriaTool {
    static let name = "ui_record_stop"
    static let description = "Stop recording and save the captured actions as a recipe."

    func run(input: [String: String]) async throws -> ToolResult {
        do {
            let recipe = try await UIRecorder.shared.stopRecording()
            return .ok("Recipe '\(recipe.name)' saved with \(recipe.steps.count) step(s).")
        } catch UIRecordingError.notRecording {
            return .ok("No recording in progress.")
        } catch {
            return .fail("Failed to stop recording: \(error.localizedDescription)")
        }
    }
}
