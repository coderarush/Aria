import Foundation

enum StepExecutor: Equatable {
    case tool(String)      // a tool name (run directly)
    case agent(String)     // a named sub-agent (Orion/Lyra/Atlas/Nova/Comet)
}

enum StepStatus: Equatable { case pending, running, done, failed }

struct TaskStep: Identifiable, Equatable {
    let id = UUID()
    var summary: String
    var executor: StepExecutor
    var input: [String: String] = [:]
    var status: StepStatus = .pending
    var result: String = ""
    /// What must hold after this step for it to count as done (v11.1.1 trust).
    var postCondition: PostCondition = .none
    static func == (l: TaskStep, r: TaskStep) -> Bool { l.id == r.id && l.status == r.status && l.result == r.result }
}

struct TaskPlan: Equatable {
    let goal: String
    var steps: [TaskStep]
    var completedCount: Int { steps.filter { $0.status == .done }.count }
    var total: Int { steps.count }
    var isComplete: Bool { !steps.isEmpty && steps.allSatisfy { $0.status == .done } }
}
