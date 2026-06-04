import SwiftUI

struct TaskPanelView: View {
    @ObservedObject var viewModel: TaskViewModel
    @State private var expanded: UUID?

    var body: some View {
        if let plan = viewModel.plan {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(plan.goal).font(.headline).lineLimit(2)
                    Spacer()
                    Button("Stop") { viewModel.onStop?() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
                Divider()
                ForEach(plan.steps) { step in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            icon(step.status)
                            Text(step.summary).font(.system(size: 13))
                            Spacer()
                            Text(executorLabel(step.executor))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { expanded = (expanded == step.id) ? nil : step.id }

                        if expanded == step.id, !step.result.isEmpty {
                            Text(step.result)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 22)
                                .lineLimit(6)
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 20)
        }
    }

    @ViewBuilder
    private func icon(_ s: StepStatus) -> some View {
        switch s {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private func executorLabel(_ e: StepExecutor) -> String {
        switch e {
        case .tool(let t): return t
        case .agent(let a): return a
        }
    }
}
