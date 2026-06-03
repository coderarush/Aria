import SwiftUI

/// First-launch onboarding: permissions one at a time + API key entry. Mic is
/// required; everything else is skippable.
struct OnboardingView: View {
    /// Called when onboarding finishes (or is skipped to the minimum).
    var onComplete: () -> Void

    @State private var step = 0
    @State private var micGranted = false
    @State private var screenNote = ""
    @State private var apiKey = ""
    @State private var apiStatus = ""

    private let steps = ["Welcome", "Microphone", "Screen", "API Key", "Done"]

    var body: some View {
        VStack(spacing: 24) {
            Text("⬡ Aria").font(.system(size: 34, weight: .bold, design: .rounded))
            ProgressView(value: Double(step), total: Double(steps.count - 1))
                .frame(width: 300)

            Group {
                switch step {
                case 0: welcome
                case 1: micStep
                case 2: screenStep
                case 3: apiStep
                default: doneStep
                }
            }
            .frame(maxWidth: 380, minHeight: 140)

            HStack {
                if step > 0 && step < steps.count - 1 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                Button(step == steps.count - 1 ? "Finish" : "Next") { advance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == 1 && !micGranted)
            }
            .frame(width: 380)
        }
        .padding(40)
        .frame(width: 520, height: 460)
    }

    private var welcome: some View {
        VStack(spacing: 10) {
            Text("Your personal AI agent that lives on your Mac.")
                .font(.title3).multilineTextAlignment(.center)
            Text("Say “Hey Aria” and it appears, listens, sees your screen, and gets things done.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var micStep: some View {
        VStack(spacing: 12) {
            Text("Microphone").font(.title2.bold())
            Text("Required for the “Hey Aria” wake word. Listening is on-device.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(micGranted ? "Granted ✓" : "Grant microphone access") {
                Task {
                    micGranted = await PermissionsManager.requestCorePermissions()
                }
            }
            .disabled(micGranted)
        }
    }

    private var screenStep: some View {
        VStack(spacing: 12) {
            Text("Screen Recording").font(.title2.bold())
            Text("Lets Aria see your screen when you ask. Captured only on command, never stored. You can skip this.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private var apiStep: some View {
        VStack(spacing: 12) {
            Text("Gemini API Key").font(.title2.bold())
            Text("Aria uses your own key (free tier works). Stored in the Keychain.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            SecureField("Paste your key", text: $apiKey).frame(width: 300)
            if !apiStatus.isEmpty { Text(apiStatus).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 10) {
            Text("You're set!").font(.title2.bold())
            Text("Say “Hey Aria” any time, or use the ⬡ menu-bar icon.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func advance() {
        if step == 3, !apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            try? KeychainManager.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                      account: KeychainKey.geminiAPIKey)
            apiStatus = "Saved."
        }
        if step >= steps.count - 1 { onComplete() }
        else { step += 1 }
    }
}
