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

// MARK: - Local voice setup (onboarding)

/// One-tap "fast local voice" setup for first-run onboarding. Pulls the fast
/// *instruct* chat model the voice path uses (default `llama3.2:3b`, or a
/// hardware-appropriate fast model) so spoken conversation can run entirely
/// on-device. Strictly OPTIONAL: a prominent "Skip — use cloud" path keeps
/// voice instant via the cloud, and a missing Ollama runtime degrades to a
/// download link rather than a crash or a hang.
///
/// Persists the chosen chat model to `UserDefaults.standard` under the key
/// `app.localChatModel`, which `LocalFirstRouter` reads for the live voice
/// chat path. Pure recommendation/label logic is `static` and unit-tested.
@MainActor
struct LocalVoiceSetupView: View {
    /// UserDefaults key the router reads for the fast chat/voice model.
    static let chatModelKey = "app.localChatModel"
    /// Shipped default fast instruct chat model (matches LocalFirstRouter).
    static let defaultChatModel = "llama3.2:3b"

    enum Phase: Equatable {
        case idle          // offer the one-tap setup
        case checking      // probing Ollama / model state
        case downloading   // pull in flight
        case ready         // model present + persisted
        case failed        // pull or start failed — retryable
        case skipped       // user chose cloud
        case ollamaMissing // runtime not installed — link out
    }

    /// Hardware-tier → fast instruct chat model for voice. Voice needs first
    /// token in ~1s and full replies in seconds, so this favors small, fast
    /// instruct models over the larger "thinking" models used for planning.
    /// Pure + unit-tested.
    static func recommendedVoiceModel(ramGB: Int) -> String {
        switch ramGB {
        case ..<16: return "llama3.2:1b"   // constrained: smallest, fastest
        default:    return defaultChatModel // 16GB+: the fast 3B sweet spot
        }
    }

    /// Human-readable name for a chat-model tag (falls back to the tag).
    static func chatDisplayName(_ tag: String) -> String {
        switch tag {
        case "llama3.2:1b": return "Llama 3.2 1B"
        case "llama3.2:3b": return "Llama 3.2 3B"
        case "llama3.1:8b": return "Llama 3.1 8B"
        default:            return tag
        }
    }

    /// Status → short label for the voice setup row. Pure + unit-tested.
    static func statusLabel(for phase: Phase) -> String {
        switch phase {
        case .idle:          return "Private voice, on this Mac"
        case .checking:      return "Checking…"
        case .downloading:   return "Downloading…"
        case .ready:         return "Ready — voice runs on-device"
        case .failed:        return "Download didn't finish"
        case .skipped:       return "Using cloud voice (already fast)"
        case .ollamaMissing: return "Runtime needed"
        }
    }

    @State private var phase: Phase = .checking
    @State private var fraction: Double = 0
    @State private var statusDetail = ""
    private let profile = HardwareProfiler.profile()

    private var model: String { Self.recommendedVoiceModel(ramGB: profile.ramGB) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.purple)
                Text("Fast local voice · \(Self.chatDisplayName(model))")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                badge
            }

            switch phase {
            case .downloading:
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: fraction)
                    Text(statusDetail.isEmpty
                         ? "Pulling \(Self.chatDisplayName(model))… you can keep going."
                         : statusDetail)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            case .ready:
                Text("Spoken conversation now runs entirely on-device — private and free. Cloud still backs it up.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .ollamaMissing:
                HStack {
                    Text("Needs Ollama — a free, one-time install. Voice already works via cloud until then.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Link("Get Ollama", destination: URL(string: "https://ollama.com/download/mac")!)
                        .font(.caption)
                    Button("Re-check") { Task { await probe() } }
                        .controlSize(.small)
                }
            case .skipped:
                Text("No problem — Aria speaks through the cloud, which is already fast. You can set up on-device voice any time in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed:
                actionRow(primaryTitle: "Try again", showSkip: true)
            case .idle:
                actionRow(primaryTitle: "Set up fast local voice", showSkip: true)
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking on-device readiness…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.purple.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.18), lineWidth: 1))
        .task { await probe() }
    }

    @ViewBuilder private var badge: some View {
        switch phase {
        case .ready:
            Label("On-device", systemImage: "checkmark.seal.fill")
                .font(.caption2).foregroundStyle(.green)
        case .skipped:
            Label("Cloud", systemImage: "cloud.fill")
                .font(.caption2).foregroundStyle(.secondary)
        case .downloading:
            Text("\(Int(fraction * 100))%")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func actionRow(primaryTitle: String, showSkip: Bool) -> some View {
        HStack(spacing: 10) {
            Text(Self.statusLabel(for: phase))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if showSkip {
                Button("Skip — use cloud") { phase = .skipped }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Button(primaryTitle) { Task { await setUp() } }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)
        }
    }

    /// Non-blocking readiness probe: if the fast model is already pulled and
    /// persisted, jump straight to ready; otherwise offer the one-tap setup.
    private func probe() async {
        phase = .checking
        let status = await ModelInstaller.currentStatus(wanted: model)
        switch status {
        case .ready:
            persistChatModel()
            phase = .ready
        case .ollamaMissing:
            phase = .ollamaMissing
        case .serverDown, .modelMissing:
            phase = .idle
        }
    }

    /// One-tap: start the server if needed, pull the fast model with live
    /// progress, persist it, never blocking the UI. Any failure is recoverable
    /// and never throws into the view.
    private func setUp() async {
        statusDetail = ""
        fraction = 0
        if await !ModelInstaller.serverAlive() {
            guard await ModelInstaller.startServer() else {
                phase = .ollamaMissing
                return
            }
        }
        phase = .downloading
        do {
            try await ModelInstaller.pull(model: model) { p in
                Task { @MainActor in
                    fraction = p.fraction
                    if !p.status.isEmpty { statusDetail = p.status }
                }
            }
            persistChatModel()
            phase = .ready
        } catch {
            statusDetail = ""
            phase = .failed
        }
    }

    /// Persist the chosen fast chat model so `LocalFirstRouter` uses it for the
    /// live voice path. Written directly to `UserDefaults.standard` (this view
    /// does not own AppSettings).
    private func persistChatModel() {
        UserDefaults.standard.set(model, forKey: Self.chatModelKey)
    }
}
