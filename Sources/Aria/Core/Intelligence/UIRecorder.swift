import Foundation

/// Errors that UIRecorder can throw.
enum UIRecordingError: Error, Equatable {
    case notRecording
    case nameRequired
}

/// Records Aria actions (via ActionLedger notifications) into a named Recipe
/// so the user can replay a workflow on demand. Start → perform actions → stop.
actor UIRecorder {
    static let shared = UIRecorder()

    private(set) var isRecording = false
    private(set) var capturedSteps: [RecipeStep] = []
    private var recordingName: String = ""

    /// Injectable for tests — replaces NotificationCenter.default observation.
    /// Called with a step-appending handler; returns a token (any Sendable) that
    /// can be used to tear down the observer. Tests typically return a no-op value.
    var observeActions: (@Sendable (@escaping @Sendable (ActionReceipt) -> Void) -> any Sendable)?

    /// Token returned by the observer registration; held so we can remove it.
    private var observerToken: (any Sendable)?

    /// Set the action observer injection (for testing from async contexts).
    func setObserveActions(_ observe: @escaping @Sendable (@escaping @Sendable (ActionReceipt) -> Void) -> any Sendable) {
        observeActions = observe
    }

    /// Start capturing actions under `name`.
    func startRecording(name: String) async {
        isRecording = true
        recordingName = name
        capturedSteps = []

        let handler: @Sendable (ActionReceipt) -> Void = { [weak self] receipt in
            Task { await self?.handleReceipt(receipt) }
        }

        if let inject = observeActions {
            observerToken = inject(handler)
        } else {
            let token = NotificationCenter.default.addObserver(
                forName: ActionLedger.didRecordNotification,
                object: nil,
                queue: nil
            ) { note in
                guard let receipt = note.userInfo?["receipt"] as? ActionReceipt else { return }
                handler(receipt)
            }
            observerToken = token
        }
    }

    /// Stop capturing, save the recipe, and return it.
    /// Throws `UIRecordingError.notRecording` when no steps were captured.
    func stopRecording(store: RecipeStore = .shared) async throws -> Recipe {
        isRecording = false
        removeObserver()

        guard !capturedSteps.isEmpty else { throw UIRecordingError.notRecording }

        let recipe = Recipe(name: recordingName, steps: capturedSteps)
        await store.upsert(recipe)
        return recipe
    }

    /// Cancel the current recording without saving anything.
    func cancel() async {
        isRecording = false
        capturedSteps = []
        recordingName = ""
        removeObserver()
    }

    // MARK: Private

    private func handleReceipt(_ receipt: ActionReceipt) {
        guard isRecording, let step = UIRecorder.step(from: receipt) else { return }
        capturedSteps.append(step)
    }

    private func removeObserver() {
        if let token = observerToken as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(token)
        }
        observerToken = nil
    }

    // MARK: ActionReceipt → RecipeStep mapping

    /// Map an ActionReceipt to a RecipeStep using the tool name and reversible info.
    /// Returns nil for actions that don't translate to replayable recipe steps.
    static func step(from receipt: ActionReceipt) -> RecipeStep? {
        switch receipt.tool {
        case "open_app":
            let name = receipt.summary  // summary is e.g. "Open Safari"
            return RecipeStep(summary: "Open \(name)", tool: "open_app", input: ["name": name])
        case "shell", "applescript":
            return RecipeStep(summary: "Run command", tool: "run_command",
                              input: ["command": receipt.summary])
        case "save_note":
            return RecipeStep(summary: "Save note", tool: "save_note",
                              input: ["title": receipt.summary])
        case "clipboard":
            // Clipboard writes: extract the text from the reversible action if present.
            var text = ""
            if case .clipboardWrite(let prev) = receipt.reversible {
                text = prev ?? ""
            }
            return RecipeStep(summary: "Copy to clipboard", tool: "clipboard_write",
                              input: ["text": text])
        default:
            return nil
        }
    }
}
