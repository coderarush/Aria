import Foundation

/// On-disk snapshot of an in-flight multi-step task, so a long objective survives a
/// crash or quit and can be resumed (directive P6: resumable workflows). One active
/// task at a time, in Application Support/Aria/active-task.json.
struct PersistedTask: Codable, Equatable {
    struct Step: Codable, Equatable {
        var summary: String
        var kind: String          // "tool" | "agent"
        var name: String
        var input: [String: String]
        var status: String        // "pending" | "done" | "failed"
        var result: String
    }
    var goal: String
    var steps: [Step]
    var lastOutput: String
    var updatedAt: Date

    var unfinishedCount: Int { steps.filter { $0.status != "done" }.count }
    var isFinished: Bool { !steps.isEmpty && steps.allSatisfy { $0.status == "done" } }
    /// Index of the first step still to run (where a resume picks up).
    var resumeIndex: Int { steps.firstIndex { $0.status != "done" } ?? steps.count }

    // MARK: Pure mapping (TaskPlan <-> PersistedTask) — unit-tested

    static func statusString(_ s: StepStatus) -> String {
        switch s {
        case .pending, .running: return "pending"   // a run that was interrupted resumes
        case .done:              return "done"
        case .failed:            return "failed"
        }
    }

    static func snapshot(goal: String, steps: [TaskStep], lastOutput: String,
                         now: Date = Date()) -> PersistedTask {
        PersistedTask(
            goal: goal,
            steps: steps.map { s in
                let kind: String, name: String
                switch s.executor {
                case .tool(let n):  kind = "tool";  name = n
                case .agent(let n): kind = "agent"; name = n
                }
                return Step(summary: s.summary, kind: kind, name: name, input: s.input,
                            status: statusString(s.status), result: s.result)
            },
            lastOutput: lastOutput, updatedAt: now)
    }

    /// Rebuild TaskSteps (with restored statuses/results) for resuming.
    func restoredSteps() -> [TaskStep] {
        steps.map { s in
            let exec: StepExecutor = (s.kind == "agent") ? .agent(s.name) : .tool(s.name)
            var step = TaskStep(summary: s.summary, executor: exec, input: s.input)
            step.status = (s.status == "done") ? .done : (s.status == "failed" ? .failed : .pending)
            step.result = s.result
            return step
        }
    }

    /// The (summary, output) of already-completed steps — restored as agent material.
    func completedPairs() -> [(summary: String, output: String)] {
        steps.filter { $0.status == "done" }.map { (summary: $0.summary, output: $0.result) }
    }
}

/// Detects a command asking to resume the interrupted task — deterministic, zero quota.
enum ResumeIntent {
    private static let phrases = [
        "resume", "pick up where", "continue the task", "continue where you left",
        "finish what you started", "finish the task", "keep going on that",
        "carry on with that", "continue that task"
    ]
    static func matches(_ command: String) -> Bool {
        let c = command.lowercased()
        return phrases.contains { c.contains($0) }
    }
}

/// Persists the single active task. An actor — written from the autonomy loop.
actor TaskStore {
    static let shared = TaskStore()

    private let url: URL
    init(url: URL? = nil) { self.url = url ?? TaskStore.defaultURL() }

    static func defaultURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aria", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("active-task.json")
    }

    func save(_ task: PersistedTask) {
        guard let data = try? JSONEncoder().encode(task) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func load() -> PersistedTask? {
        guard let data = try? Data(contentsOf: url),
              let t = try? JSONDecoder().decode(PersistedTask.self, from: data) else { return nil }
        return t
    }

    func clear() { try? FileManager.default.removeItem(at: url) }

    /// A resumable task: one that exists and still has unfinished steps.
    func pending() -> PersistedTask? {
        guard let t = load(), !t.isFinished, t.unfinishedCount > 0 else { return nil }
        return t
    }
}
