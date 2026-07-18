import Foundation

/// How Glass is presenting (spec §101).
enum GlassMode: String, Sendable { case focus, ambient, glance, recall }

/// The Glass Alpha experience (spec §101) — extends ``GlassRuntime`` to display
/// objectives, continue context, surface recall, and support delegation. It has
/// NO execution, NO planning, and NO tool calls.
actor GlassExperience {

    private let glass: GlassRuntime
    private(set) var mode: GlassMode = .ambient

    init(glass: GlassRuntime) {
        self.glass = glass
    }

    func setMode(_ mode: GlassMode) { self.mode = mode }

    /// Display current state; focus when there's an objective, else ambient.
    func display(_ stream: StreamState) async {
        mode = stream.objective == nil ? .ambient : .focus
        await glass.render(stream)
    }

    /// Surface reconstructed context in recall mode.
    func showRecall(_ bundle: RecallBundle) async {
        mode = .recall
        await glass.render(StreamState(
            objective: bundle.objective,
            status: "recall",
            attention: "recall",
            context: bundle.summary,
            memory: bundle.recentActions))
    }
}
