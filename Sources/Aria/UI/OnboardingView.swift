import SwiftUI

/// First-launch onboarding (V11 FRE): permissions → local model → key →
/// persona + workflow pack → first briefing. The first five minutes should
/// already feel like Aria works for you. Mic is required; everything else
/// is skippable.
struct OnboardingView: View {
    /// Called when onboarding finishes (or is skipped to the minimum).
    var onComplete: () -> Void

    @StateObject private var settings = AppSettings.shared
    @State private var step = 0
    @State private var micGranted = false
    @State private var apiKey = ""
    @State private var apiStatus = ""
    @State private var persona = ""
    @State private var packStatus = ""
    @State private var briefingText = ""
    @State private var briefingRunning = false

    // Steps: 0=Welcome 1=Mic 2=Screen 3=LocalModel 4=APIKey 5=Persona 6=Briefing 7=Done
    private let totalSteps = 8

    private var stepIcon: String {
        switch step {
        case 0: return "hand.wave.fill"
        case 1: return "mic.fill"
        case 2: return "rectangle.dashed.badge.record"
        case 3: return "cpu"
        case 4: return "key.fill"
        case 5: return "person.crop.circle.badge.checkmark"
        case 6: return "sun.max.fill"
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
                    case 3: localModelStep
                    case 4: apiStep
                    case 5: personaStep
                    case 6: briefingStep
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

    private var localModelStep: some View {
        VStack(spacing: 12) {
            Text("Your Private Model")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Aria runs everyday work on a model that lives on this Mac \u{2014} private, free, no quota. One click and she picks the right size for your hardware.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            LocalModelSetupView(compact: true)
                .frame(maxWidth: 380)
                .padding(.top, 4)
            Text("You can skip this \u{2014} Aria works with cloud models too.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var personaStep: some View {
        VStack(spacing: 12) {
            Text("How will you use Aria?")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Picks your starter workflows \u{2014} briefings, prep, focus. Everything stays editable in Settings \u{2192} Recipes.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            HStack(spacing: 10) {
                ForEach(WorkflowPack.builtins) { pack in
                    Button {
                        persona = pack.persona
                        packStatus = ""
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: personaIcon(pack.persona))
                                .font(.system(size: 20))
                            Text(pack.persona).font(.system(size: 12, weight: .semibold))
                        }
                        .frame(width: 96, height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(persona == pack.persona
                                      ? settings.accentColor.opacity(0.2)
                                      : Color.secondary.opacity(0.08)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(persona == pack.persona ? settings.accentColor : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            if !packStatus.isEmpty {
                Text(packStatus).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var briefingStep: some View {
        VStack(spacing: 12) {
            Text("Your First Briefing")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            if briefingText.isEmpty {
                Text("Aria reads your calendar, reminders and recent work, and tells you what the day looks like. Try it now \u{2014} this is the \u{201C}brief me\u{201D} you'll use every morning.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                Button {
                    briefingRunning = true
                    Task { @MainActor in
                        let (text, _) = await BriefingComposer.compose(gemini: GeminiClient())
                        briefingText = text
                        briefingRunning = false
                    }
                } label: {
                    if briefingRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Brief me", systemImage: "sun.max")
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(settings.accentColor)
                .disabled(briefingRunning)
                .padding(.top, 4)
            } else {
                ScrollView {
                    Text(briefingText)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 150)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.07)))
            }
        }
    }

    private func personaIcon(_ persona: String) -> String {
        switch persona.lowercased() {
        case "founder": return "briefcase.fill"
        case "student": return "graduationcap.fill"
        default: return "chevron.left.forwardslash.chevron.right"
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
        if step == 4, !apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            try? KeychainManager.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                      account: KeychainKey.geminiAPIKey)
            apiStatus = "Saved."
        }
        // Leaving the persona step installs the matching workflow pack.
        if step == 5, !persona.isEmpty, let pack = WorkflowPack.forPersona(persona) {
            settings.personaChoice = persona
            Task {
                await PackInstaller.install(pack)
                NotificationCenter.default.post(name: .ariaAgentsChanged, object: nil)
            }
        }
        if step >= totalSteps - 1 {
            onComplete()
        } else {
            step += 1
        }
    }
}
