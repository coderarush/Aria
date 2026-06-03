import SwiftUI

/// Aria's settings window. Tabs map to the spec's settings sections.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            APIKeyTab()
                .tabItem { Label("API Key", systemImage: "key") }
            ToolsTab()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            DynamicToolsTab()
                .tabItem { Label("Dynamic", systemImage: "sparkles") }
            BrainTab()
                .tabItem { Label("Brain", systemImage: "brain") }
            MirrorTab()
                .tabItem { Label("Mirror", systemImage: "rectangle.on.rectangle") }
        }
        .frame(width: 480, height: 420)
    }
}

// MARK: General

struct GeneralSettingsTab: View {
    @StateObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Picker("Orb position", selection: $settings.orbPosition) {
                ForEach(AppSettings.OrbPosition.allCases) { Text($0.label).tag($0) }
            }
            Picker("Orb size", selection: $settings.orbSize) {
                ForEach(AppSettings.OrbSize.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
            HStack {
                Text("Response duration")
                Slider(value: $settings.responseDuration, in: 3...20, step: 1)
                Text("\(Int(settings.responseDuration))s").monospacedDigit()
            }
            Toggle("Privacy mode (disable screen capture)", isOn: $settings.privacyMode)
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
        }
        .padding()
    }
}

// MARK: API key

struct APIKeyTab: View {
    @State private var key: String = ""
    @State private var status: String = ""

    var body: some View {
        Form {
            SecureField("Gemini API key", text: $key)
            HStack {
                Button("Save") { save() }
                Button("Clear") {
                    KeychainManager.delete(account: KeychainKey.geminiAPIKey)
                    key = ""; status = "Cleared."
                }
            }
            if !status.isEmpty { Text(status).foregroundStyle(.secondary).font(.caption) }
            Text("Stored in the macOS Keychain. Get a key at aistudio.google.com.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { key = KeychainManager.read(account: KeychainKey.geminiAPIKey) ?? "" }
    }

    private func save() {
        do {
            try KeychainManager.save(key.trimmingCharacters(in: .whitespacesAndNewlines),
                                     account: KeychainKey.geminiAPIKey)
            status = "Saved to Keychain."
        } catch { status = "Save failed: \(error.localizedDescription)" }
    }
}

// MARK: Tools

struct ToolsTab: View {
    @StateObject private var settings = AppSettings.shared
    private let toolNames = ToolRegistry.builtins().map { type(of: $0).name }.sorted()

    var body: some View {
        Form {
            Text("Enabled tools").font(.headline)
            ForEach(toolNames, id: \.self) { name in
                Toggle(name, isOn: Binding(
                    get: { !settings.disabledTools.contains(name) },
                    set: { on in
                        if on { settings.disabledTools.remove(name) }
                        else { settings.disabledTools.insert(name) }
                    }))
            }
        }
        .padding()
    }
}

// MARK: Dynamic tools

struct DynamicToolsTab: View {
    @State private var s = DynamicToolSettings.load()

    var body: some View {
        Form {
            Toggle("Allow Aria to write and run code", isOn: $s.allowCodeExecution)
            Toggle("Show code before running", isOn: $s.showCodeBeforeRun)
            Toggle("Ask before saving new tools", isOn: $s.askBeforeSaving)
            Toggle("Sync community tools", isOn: $s.syncCommunityTools)
            Text("Generated tools live in Application Support/Aria/tools.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .onChange(of: s.allowCodeExecution) { _, _ in s.save() }
        .onChange(of: s.showCodeBeforeRun) { _, _ in s.save() }
        .onChange(of: s.askBeforeSaving) { _, _ in s.save() }
        .onChange(of: s.syncCommunityTools) { _, _ in s.save() }
    }
}

// MARK: Brain (learning)

struct BrainTab: View {
    @State private var s = LearningSettings.load()

    var body: some View {
        Form {
            Toggle("Learning enabled", isOn: $s.enabled)
            Toggle("Pause all automations", isOn: $s.automationsPaused)
            HStack {
                Text("Sensitivity")
                Slider(value: $s.sensitivity, in: 0.6...0.9, step: 0.05)
                Text(label(for: s.sensitivity)).font(.caption).frame(width: 90, alignment: .trailing)
            }
            Text("Conservative requires more confidence before suggesting; Aggressive suggests sooner.")
                .font(.caption).foregroundStyle(.secondary)
            Text("All learning happens on-device. Nothing is sent anywhere.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .onChange(of: s.enabled) { _, _ in s.save() }
        .onChange(of: s.automationsPaused) { _, _ in s.save() }
        .onChange(of: s.sensitivity) { _, _ in s.save() }
    }

    private func label(for v: Double) -> String {
        v >= 0.85 ? "Conservative" : v <= 0.65 ? "Aggressive" : "Balanced"
    }
}

// MARK: Mirror

struct MirrorTab: View {
    @State private var s = MirrorSettings.load()
    @State private var portText = "8765"

    var body: some View {
        Form {
            Toggle("Enable Mirror Bridge", isOn: $s.enabled)
            TextField("Port", text: $portText)
            HStack {
                Circle().fill(s.enabled ? .green : .gray).frame(width: 8, height: 8)
                Text(s.enabled ? MirrorBridge.ConnectionState.notConnected.rawValue : "Disabled")
                    .foregroundStyle(.secondary)
            }
            Text("Set-up guide coming soon.").font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { portText = String(s.port) }
        .onChange(of: s.enabled) { _, _ in persist() }
        .onChange(of: portText) { _, _ in persist() }
    }

    private func persist() {
        s.port = Int(portText) ?? 8765
        s.save()
    }
}
