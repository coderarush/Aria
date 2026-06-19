import SwiftUI

@MainActor
final class TaskViewModel: ObservableObject {
    @Published var plan: TaskPlan?
    @Published var isVisible = false
    var onStop: (() -> Void)?
    var onVisibilityChange: ((Bool) -> Void)?

    func show(_ plan: TaskPlan) { self.plan = plan; setVisible(true) }

    func markRunning(_ i: Int) {
        guard plan != nil, plan!.steps.indices.contains(i) else { return }
        plan!.steps[i].status = .running
    }

    func markFinished(_ i: Int, ok: Bool, result: String) {
        guard plan != nil, plan!.steps.indices.contains(i) else { return }
        plan!.steps[i].status = ok ? .done : .failed
        plan!.steps[i].result = result
    }

    func hide() { setVisible(false) }

    private func setVisible(_ v: Bool) {
        guard isVisible != v else { return }
        isVisible = v
        onVisibilityChange?(v)
    }
}
