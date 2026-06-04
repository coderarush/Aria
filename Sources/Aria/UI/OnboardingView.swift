import SwiftUI

/// First-launch onboarding: permissions one at a time + API key entry. Mic is
/// required; everything else is skippable.
struct OnboardingView: View {
    /// Called when onboarding finishes (or is skipped to the minimum).
    var onComplete: () -> Void

    @StateObject private var settings = AppSettings.shared
    @State private var step = 0
    @State private var micGranted = false
    @State private var apiKey = ""
    @State private var apiStatus = ""

    // Steps: 0=Welcome 1=Mic 2=Screen 3=APIKey 4=Voice 5=Done
    private let totalSteps = 6

    private var stepIcon: String {
        switch step {
        case 0: return "hand.wave.fill"
        case 1: return "mic.fill"
        case 2: return "rectangle.dashed.badge.record"
        case 3: return "key.fill"
        case 4: return "speaker.wave.2.fill"
        default: return "checkmark.seal.fill"
        }
    }

    var body: some View {
        ZStack {
            // Soft gradient backdrop
            LinearGradient(
                colors: [
                    settings.accentColor.opacity(0.12),
                    Color(NSColor.windowBackgroundColor).opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header: logo
                VStack(spacing: 6) {
                    Text("⬡ Aria")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(settings.accentColor)
                }
                .padding(.top, 36)
                .padding(.bottom, 20)

                // Dot progress indicator
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Circle()
                            .fill(i <= step ? settings.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: i == step ? 10 : 7, height: i == step ? 10 : 7)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: step)
                    }
                }
                .padding(.bottom, 28)

                // Step icon
                Image(systemName: stepIcon)
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(settings.accentColor)
                    .padding(.bottom, 16)
                    .transition(.scale.combined(with: .opacity))
                    .id("icon-\(step)")
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: step)

                // Step content
                Group {
                    switch step {
                    case 0: welcome
                    case 1: micStep
                    case 2: screenStep
                    case 3: apiStep
                    case 4: voiceStep
                    default: doneStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id("step-\(step)")
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
                .frame(maxWidth: 400, minHeight: 130)
                .padding(.horizontal, 24)

                Spacer(minLength: 20)

                // Navigation buttons
                HStack(spacing: 12) {
                    if step > 0 && step < totalSteps - 1 {
                        Button {
                            withAnimation { step -= 1 }
                        } label: {
                            Text("Back")
                                .frame(minWidth: 72)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Spacer()

                    Button {
                        withAnimation { advance() }
                    } label: {
                        Text(step == totalSteps - 1 ? "Finish" : "Continue")
                            .fontWeight(.semibold)
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(settings.accentColor)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == 1 && !micGranted)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
            }
        }
        .frame(width: 560, height: 500)
    }

    // MARK: Step views

    private var welcome: some View {
        VStack(spacing: 12) {
            Text("Welcome to Aria")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Your personal AI agent that lives on your Mac.")
                .font(.title3)
                .multilineTextAlignment(.center)
            Text("Say \u{201C}Hey Aria\u{201D} and it appears, listens, sees your screen, and gets things done.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var micStep: some View {
        VStack(spacing: 12) {
            Text("Microphone Access")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Required to hear \u{201C}Hey Aria.\u{201D} All wake-word detection runs on-device \u{2014} nothing is sent to the cloud.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Button {
                Task { micGranted = await PermissionsManager.requestCorePermissions() }
            } label: {
                Label(
                    micGranted ? "Microphone granted" : "Grant microphone access",
                    systemImage: micGranted ? "checkmark.circle.fill" : "mic.badge.plus"
                )
                .fontWeight(.medium)
            }
            .disabled(micGranted)
            .tint(micGranted ? .green : settings.accentColor)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 4)
        }
    }

    private var screenStep: some View {
        VStack(spacing: 12) {
            Text("Screen Recording")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Lets Aria see your screen when you ask. Captured only on command, never stored continuously. You can skip this and enable it later.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open Privacy Settings", systemImage: "arrow.up.right.square")
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, 4)
        }
    }

    private var apiStep: some View {
        VStack(spacing: 12) {
            Text("Gemini API Key")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Aria uses your own key \u{2014} the free tier works. Stored securely in the macOS Keychain, never transmitted elsewhere.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            SecureField("Paste your API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .padding(.top, 4)
            if !apiStatus.isEmpty {
                Text(apiStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var voiceStep: some View {
        VStack(spacing: 12) {
            Text("Aria\u{2019}s Voice")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Image(systemName: "waveform")
                .font(.system(size: 34))
                .foregroundStyle(settings.accentColor)
            Text("Aria speaks with a natural Gemini voice — no setup needed. You can pick a different voice any time in Settings \u{2192} Voice.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var doneStep: some View {
        VStack(spacing: 12) {
            Text("You\u{2019}re all set!")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Say \u{201C}Hey Aria\u{201D} any time, or tap the \u{2B21} menu-bar icon to get started.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    // MARK: Navigation

    private func advance() {
        // Save API key when leaving API step
        if step == 3, !apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            try? KeychainManager.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                      account: KeychainKey.geminiAPIKey)
            apiStatus = "Saved."
        }
        if step >= totalSteps - 1 {
            onComplete()
        } else {
            step += 1
        }
    }
}
