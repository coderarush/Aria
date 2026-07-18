import Foundation

extension Notification.Name {
    /// Carries no task content. Desktop surfaces re-read their privacy-safe
    /// snapshot after this event rather than retaining execution data themselves.
    static let ariaTaskStoreDidChange = Notification.Name("aria.taskStoreDidChange")
}

/// On-disk snapshot of an in-flight multi-step task, so a long objective survives a
/// crash or quit and can be resumed (directive P6: resumable workflows). One active
/// task at a time, in Application Support/Aria/active-task.json.
struct PersistedTask: Codable, Equatable, Sendable {
    struct Step: Codable, Equatable, Sendable {
        var summary: String
        var kind: String          // "tool" | "agent"
        var name: String
        var input: [String: String]
        var status: String        // "pending" | "done" | "failed"
        var result: String
        /// Optional so active-task files created before verified contracts remain
        /// decodable and resume with the old `.none` behavior.
        var postCondition: PostCondition?
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
                            status: statusString(s.status), result: s.result,
                            postCondition: s.postCondition)
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
            step.postCondition = s.postCondition ?? .none
            return step
        }
    }

    /// The (summary, output) of already-completed steps — restored as agent material.
    func completedPairs() -> [(summary: String, output: String)] {
        steps.filter { $0.status == "done" }.map { (summary: $0.summary, output: $0.result) }
    }
}

/// Whether the active-task snapshot belongs to an execution still running in
/// this process or work discovered after launch that can be resumed. This is
/// deliberately process-local: timestamps would guess, while this state is
/// exact for both cases.
enum TaskRunState: Sendable, Equatable {
    case running
    case resumable
}

/// The privacy-safe store result used by surfaces that need task continuity.
/// Consumers render only task metadata; raw input and output remain in the
/// persisted task for execution/resume, not dashboard presentation.
struct CurrentTaskSnapshot: Sendable, Equatable {
    let task: PersistedTask
    let state: TaskRunState
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

/// Notification copy for interrupted work. It intentionally accepts only a
/// count, so a task goal, step summary, input, or output cannot reach a
/// system notification that may be visible outside Aria.
enum ResumeNotificationPresentation {
    static func body(remainingSteps: Int) -> String {
        let count = max(remainingSteps, 0)
        let steps = count == 1 ? "1 step" : "\(count) steps"
        return "An unfinished task is ready to resume (\(steps) left). Open Aria or say “resume” to continue."
    }
}

/// Persists the single active task. An actor — written from the autonomy loop.
actor TaskStore {
    static let shared = TaskStore()

    private let url: URL
    private var isRunningInCurrentProcess = false
    init(url: URL? = nil) { self.url = url ?? TaskStore.defaultURL() }

    static func defaultURL() -> URL {
        PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("active-task.json")
    }

    func save(_ task: PersistedTask) {
        guard let data = try? JSONEncoder().encode(task) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            isRunningInCurrentProcess = true
            NotificationCenter.default.post(name: .ariaTaskStoreDidChange, object: nil)
        } catch {
            Log.trace("task store: couldn't persist active task")
        }
    }

    func load() -> PersistedTask? {
        guard let data = try? Data(contentsOf: url),
              let t = try? JSONDecoder().decode(PersistedTask.self, from: data) else { return nil }
        return t
    }

    func clear() {
        isRunningInCurrentProcess = false
        try? FileManager.default.removeItem(at: url)
        NotificationCenter.default.post(name: .ariaTaskStoreDidChange, object: nil)
    }

    /// A resumable task: one that exists and still has unfinished steps.
    func pending() -> PersistedTask? {
        guard let t = load(), !t.isFinished, t.unfinishedCount > 0 else { return nil }
        return t
    }

    /// The active task with an exact current-process/relaunch distinction for
    /// Home and other read-only surfaces.
    func currentTask() -> CurrentTaskSnapshot? {
        guard let task = pending() else { return nil }
        return CurrentTaskSnapshot(task: task,
                                   state: isRunningInCurrentProcess ? .running : .resumable)
    }
}
