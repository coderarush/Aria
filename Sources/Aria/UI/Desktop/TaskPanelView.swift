import SwiftUI

struct TaskPanelView: View {
    @ObservedObject var viewModel: TaskViewModel
    @State private var expanded: UUID?

    var body: some View {
        if let plan = viewModel.plan {
            let presentation = TaskProgressPresentation(plan: plan)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Work in progress")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(plan.goal)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        viewModel.onStop?()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                        .accessibilityHint("Stops the current task.")
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        AriaStatusBadge(title: presentation.statusText, symbol: "checklist", tint: .accentColor)
                        Spacer()
                        Text("\(presentation.completedCount)/\(presentation.totalCount)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: presentation.fraction)
                        .tint(.accentColor)
                        .accessibilityLabel("Task progress")
                        .accessibilityValue(presentation.statusText)
                    if let currentStep = presentation.currentStep {
                        Label("Current: \(currentStep)", systemImage: "arrow.right.circle.fill")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Divider().opacity(0.6)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(plan.steps) { step in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    icon(step.status)
                                    Text(step.summary)
                                        .font(.system(size: 13, weight: step.status == .running ? .semibold : .regular))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(executorLabel(step.executor))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
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
                }
                .frame(maxHeight: 220)
            }
            .padding(18)
            .frame(width: 420)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AriaVisualMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AriaVisualMetrics.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.16), radius: 20, y: 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
