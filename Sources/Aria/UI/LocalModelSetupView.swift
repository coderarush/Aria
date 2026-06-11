import SwiftUI

/// V11 P1 — one-click local model setup, embedded in Settings → Keys and in
/// onboarding. Shows the hardware-based recommendation, current status, a
/// single action button, and live pull progress. Health appears once local
/// generation has actually run.
struct LocalModelSetupView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var profile = HardwareProfiler.profile()
    @State private var status: ModelInstaller.SetupStatus?
    @State private var pulling = false
    @State private var pullFraction: Double = 0
    @State private var pullStatus = ""
    @State private var health: LocalModelHealth.Snapshot?
    @State private var message = ""

    /// Compact: onboarding (no health, tighter copy). Full: Settings.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cpu")
                Text("\(profile.chip) · \(profile.ramGB) GB · recommends \(displayName(profile.recommendedModel))")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                statusBadge
            }

            if pulling {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: pullFraction)
                    Text(pullStatus.isEmpty ? "Downloading \(displayName(wantedModel))…" : pullStatus)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else if let status {
                actionRow(for: status)
            }

            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }

            if !compact, let health, health.successes + health.failures > 0 {
                HStack(spacing: 12) {
                    Label("\(health.successes) ok", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                    if health.failures > 0 {
                        Label("\(health.failures) failed", systemImage: "xmark.circle")
                            .foregroundStyle(.orange)
                    }
                    if let l = health.lastLatency {
                        Text(String(format: "last reply %.1fs", l)).foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
            }
        }
        .task { await refresh() }
    }

    private var wantedModel: String {
        settings.localModelName.isEmpty ? profile.recommendedModel : settings.localModelName
    }

    private func displayName(_ tag: String) -> String {
        switch tag {
        case "qwen3:4b": return "Qwen 3 4B"
        case "qwen3:8b": return "Qwen 3 8B"
        case "qwen3:14b": return "Qwen 3 14B"
        default: return tag
        }
    }

    @ViewBuilder private var statusBadge: some View {
        switch status {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .modelMissing, .serverDown:
            Label("Setup needed", systemImage: "arrow.down.circle")
                .font(.caption).foregroundStyle(.orange)
        case .ollamaMissing:
            Label("Runtime missing", systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(.orange)
        case nil:
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder private func actionRow(for status: ModelInstaller.SetupStatus) -> some View {
        switch status {
        case .ollamaMissing:
            HStack {
                Text("Aria runs models through Ollama — a free, one-time install.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Link("Get Ollama", destination: URL(string: "https://ollama.com/download/mac")!)
                Button("Re-check") { Task { await refresh() } }
            }
        case .serverDown:
            HStack {
                Text("Ollama is installed but not running.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Start & set up") { Task { await startAndInstall() } }
            }
        case .modelMissing:
            HStack {
                Text("One download and everything private runs on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Install \(displayName(profile.recommendedModel))") {
                    Task { await startAndInstall() }
                }
            }
        case .ready:
            EmptyView()
        }
    }

    @MainActor private func refresh() async {
        status = await ModelInstaller.currentStatus(wanted: wantedModel)
        health = await LocalModelHealth.shared.snapshot()
        if status == .ready { message = "" }
    }

    @MainActor private func startAndInstall() async {
        message = ""
        if await !ModelInstaller.serverAlive() {
            guard await ModelInstaller.startServer() else {
                message = "Couldn't start Ollama — open the Ollama app once, then re-check."
                await refresh()
                return
            }
        }
        // Adopt the recommendation when the user hasn't picked a model.
        if settings.localModelName.isEmpty { settings.localModelName = profile.recommendedModel }
        let model = wantedModel
        pulling = true
        defer { pulling = false }
        do {
            try await ModelInstaller.pull(model: model) { p in
                Task { @MainActor in
                    pullFraction = p.fraction
                    if !p.status.isEmpty { pullStatus = p.status }
                }
            }
            message = "\(displayName(model)) is ready — private, free, on this Mac."
        } catch {
            message = "Download didn't finish — check your connection and try again."
        }
        await refresh()
    }
}
