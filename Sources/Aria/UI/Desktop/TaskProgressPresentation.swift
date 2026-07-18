import Foundation

/// View-independent progress for the floating execution monitor. It contains
/// status metadata only, never step input or unbounded tool output.
struct TaskProgressPresentation: Equatable, Sendable {
    let completedCount: Int
    let totalCount: Int
    let fraction: Double
    let currentStep: String?
    let statusText: String

    init(plan: TaskPlan) {
        totalCount = plan.steps.count
        completedCount = plan.steps.filter { $0.status == .done }.count
        currentStep = plan.steps.first(where: { $0.status == .running })?.summary
            ?? plan.steps.first(where: { $0.status == .pending })?.summary
        fraction = totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)

        if totalCount == 0 {
            statusText = "Preparing work"
        } else if completedCount == totalCount {
            statusText = "Complete"
        } else if currentStep == nil, plan.steps.contains(where: { $0.status == .failed }) {
            statusText = "Needs attention"
        } else {
            statusText = "\(completedCount) of \(totalCount) steps complete"
        }
    }
}
