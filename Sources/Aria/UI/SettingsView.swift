import SwiftUI

/// Aria's settings window — sidebar layout.
struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general = "General", voice = "Voice", conversation = "Conversation",
             apiKey = "API Key", memory = "Memory", tools = "Tools", dynamic = "Dynamic", brain = "Brain", mirror = "Mirror", crew = "Crew"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general:      return "gearshape"
            case .voice:        return "speaker.wave.2"
            case .conversation: return "bubble.left.and.bubble.right"
            case .apiKey:       return "key"
            case .memory:       return "brain.head.profile"
            case .tools:        return "wrench.and.screwdriver"
            case .dynamic:      return "sparkles"
            case .brain:        return "brain"
            case .mirror:       return "rectangle.on.rectangle"
            case .crew:         return "person.3"
            }
        }
    }

    @State private var selection: Section = .general

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            ScrollView {
                detailView
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(selection.rawValue)
        }
        .frame(width: 720, height: 500)
    }

    @ViewBuilder private var detailView: some View {
        switch selection {
        case .general:      GeneralSettingsTab()
        case .voice:        VoiceSettingsTab()
        case .conversation: ConversationSettingsTab()
        case .apiKey:       APIKeyTab()
        case .memory:       MemorySettingsTab()
        case .tools:        ToolsTab()
        case .dynamic:      DynamicToolsTab()
        case .brain:        BrainTab()
        case .mirror:       MirrorTab()
        case .crew:         CrewSettingsTab()
        }
    }
}

// MARK: General

struct GeneralSettingsTab: View {
    @StateObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Appearance & Behavior")
                .font(.title3.bold())
            Text("Customize Aria\u{2019}s look and runtime behavior.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)

        Form {
            Section {
                Picker("Accent", selection: Binding(
                    get: { settings.accentChoiceRaw },
                    set: { settings.accentChoiceRaw = $0 })) {
                    Text("Follow system").tag("system")
                    ForEach(Theme.presets, id: \.id) { p in
                        Text(p.name).tag("preset:\(p.id)")
                    }
                    Text("Custom\u{2026}").tag(customTag)
                }
                if settings.accentChoiceRaw.hasPrefix("custom:") || settings.accentChoiceRaw == customTag {
                    ColorPicker("Custom color", selection: customColorBinding, supportsOpacity: false)
                }
                HStack(spacing: 8) {
                    Text("Preview").foregroundStyle(.secondary)
                    Capsule().fill(settings.accentColor).frame(width: 60, height: 10)
                }
                Picker("Aurora palette", selection: $settings.glowPaletteID) {
                    ForEach(Theme.glowPalettes, id: \.id) { Text($0.name).tag($0.id) }
                }
            } header: { Text("Accent Color") }

            Section {
                HStack {
                    Text("Response duration")
                    Slider(value: $settings.responseDuration, in: 3...20, step: 1)
                    Text("\(Int(settings.responseDuration))s").monospacedDigit()
                }
                Toggle("Privacy mode (disable screen capture)", isOn: $settings.privacyMode)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            } header: { Text("Behavior") }
        }
        .formStyle(.grouped)
    }

    private let customTag = "custom:#3B82F6"

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { settings.accentColor },
            set: { newColor in
                let ns = NSColor(newColor).usingColorSpace(.sRGB) ?? .systemBlue
                let hex = String(format: "#%02X%02X%02X",
                                 Int(ns.redComponent * 255),
                                 Int(ns.greenComponent * 255),
                                 Int(ns.blueComponent * 255))
                settings.accentChoiceRaw = "custom:\(hex)"
            })
    }
}

// MARK: Conversation

struct ConversationSettingsTab: View {
    @StateObject private var settings = AppSettings.shared
    @State private var axOK = AXReader.hasPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Conversation")
                .font(.title3.bold())
            Text("How Aria listens and lets you interrupt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)

        Form {
            Section {
                HStack {
                    Text("End conversation after silence")
                    Slider(value: $settings.conversationSilenceTimeout, in: 5...20, step: 1)
                    Text("\(Int(settings.conversationSilenceTimeout))s").monospacedDigit()
                }
                Text("Talk to Aria in a continuous back-and-forth — after she answers, just speak your next question (no need to say “Hey Aria” again). She stops listening after this much silence.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Let me interrupt her (talk-over)", isOn: $settings.bargeInEnabled)
                if settings.bargeInEnabled {
                    HStack {
                        Text("Interrupt sensitivity")
                        Slider(value: $settings.bargeInSensitivity, in: 0...1, step: 0.05)
                        Text(settings.bargeInSensitivity < 0.34 ? "Low" : settings.bargeInSensitivity < 0.67 ? "Med" : "High")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text("Start talking while Aria is speaking and she'll stop and listen — powered by on-device echo cancellation. Higher sensitivity interrupts more easily (but may trigger on background noise).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Barge-in") }

            Section {
                Toggle("Only respond to my voice", isOn: $settings.speakerVerificationEnabled)
                Button("Teach Aria my voice") { NotificationCenter.default.post(name: .ariaEnrollVoice, object: nil) }
                Text("Experimental. After enabling, click “Teach Aria my voice”, then say “Hey Aria” a few times. She'll bias toward your voice and ignore others. Basic on-device voiceprint — not a hard security guarantee.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Speaker verification") }

            Section {
                HStack {
                    Text("Accessibility access")
                    Spacer()
                    Text(axOK ? "Granted" : "Not granted")
                        .font(.callout).foregroundStyle(axOK ? Color.green : Color.secondary)
                }
                if !axOK {
                    Button("Grant access\u{2026}") {
                        AXReader.requestPermission()
                        axOK = AXReader.hasPermission
                    }
                }
                Text("Lets Aria see and operate your apps \u{2014} click, type, run menus, scroll \u{2014} by voice. Required for computer-use commands. Aria asks before anything destructive and shows an indicator while in control, which you can stop.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Computer use") }
        }
        .formStyle(.grouped)
        .onAppear { axOK = AXReader.hasPermission }
    }
}

// MARK: API key

struct APIKeyTab: View {
    @StateObject private var settings = AppSettings.shared
    @State private var key: String = ""
    @State private var groq: String = ""
    @State private var cerebras: String = ""
    @State private var openRouter: String = ""
    @State private var status: String = ""

    private var keyCount: Int {
        key.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your Gemini Keys")
                .font(.title3.bold())
            Text("Stored securely in the macOS Keychain. Never transmitted by Aria.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)

        Form {
            Section {
                TextEditor(text: $key)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                HStack {
                    Button("Save") { save() }.buttonStyle(.borderedProminent)
                    Button("Clear") {
                        KeychainManager.delete(account: KeychainKey.geminiAPIKey)
                        key = ""; status = "Cleared."
                    }
                    Spacer()
                    Text("\(keyCount) key\(keyCount == 1 ? "" : "s")").foregroundStyle(.secondary).font(.caption)
                }
                if !status.isEmpty { Text(status).foregroundStyle(.green).font(.caption) }
                Text("One key per line. Aria rotates across them — when one hits its daily free-tier limit, she switches to the next. **Click Save** after pasting.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("API Keys") }

            Section {
                Text("Get free keys at aistudio.google.com. Each Google project has its own free daily quota, so adding 2–3 keys from different projects multiplies how much you can do for free.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("More free quota") }

            Section {
                SecureField("Groq key (groq.com — free, fast)", text: $groq)
                SecureField("Cerebras key (cerebras.ai — free, fast)", text: $cerebras)
                SecureField("OpenRouter key (openrouter.ai — free tier)", text: $openRouter)
                Text("When your Gemini quota runs out, Aria automatically continues on these free, fast providers — so she keeps working. Each is free to sign up; add any you like, then Save.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Free fallback providers") }

            Section {
                Toggle("Use a local model when everything else is out (Ollama)", isOn: $settings.localModelEnabled)
                if settings.localModelEnabled {
                    TextField("Ollama model", text: $settings.localModelName)
                    Text("Last resort — works offline. Requires Ollama running (ollama.com) with the model pulled. Slower, but never hits a limit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Local model") }
        }
        .formStyle(.grouped)
        .onAppear {
            key = KeychainManager.read(account: KeychainKey.geminiAPIKey) ?? ""
            groq = KeychainManager.read(account: KeychainKey.groqAPIKey) ?? ""
            cerebras = KeychainManager.read(account: KeychainKey.cerebrasAPIKey) ?? ""
            openRouter = KeychainManager.read(account: KeychainKey.openRouterAPIKey) ?? ""
        }
    }

    private func save() {
        func put(_ v: String, _ account: String) {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { KeychainManager.delete(account: account) } else { try? KeychainManager.save(t, account: account) }
        }
        put(key, KeychainKey.geminiAPIKey)
        put(groq, KeychainKey.groqAPIKey)
        put(cerebras, KeychainKey.cerebrasAPIKey)
        put(openRouter, KeychainKey.openRouterAPIKey)
        status = "Saved \(keyCount) Gemini key\(keyCount == 1 ? "" : "s") + providers to Keychain."
    }
}

// MARK: Memory

struct MemorySettingsTab: View {
    @State private var facts: [MemoryFact] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What Aria Remembers")
                .font(.title3.bold())
            Text("Durable facts Aria recalls across sessions. Say “remember that …” to add one.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4).padding(.bottom, 8)

        Form {
            Section {
                if facts.isEmpty {
                    Text("Nothing remembered yet.").foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(facts) { fact in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(fact.text).font(.system(size: 13))
                                Text(fact.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await LongTermMemory.shared.forget(id: fact.id); await reload() }
                            } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                    }
                }
            } header: { Text("Memories (\(facts.count))") }

            if !facts.isEmpty {
                Section {
                    Button("Forget everything", role: .destructive) {
                        Task { await LongTermMemory.shared.clear(); await reload() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await reload() }
    }

    private func reload() async {
        facts = await LongTermMemory.shared.all().sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: Tools

struct ToolsTab: View {
    @StateObject private var settings = AppSettings.shared
    private let toolNames = ToolRegistry.builtins().map { type(of: $0).name }.sorted()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tool Permissions")
                .font(.title3.bold())
            Text("Choose which built-in tools Aria can use on your behalf.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)

        Form {
            Section {
                ForEach(toolNames, id: \.self) { name in
                    Toggle(name, isOn: Binding(
                        get: { !settings.disabledTools.contains(name) },
                        set: { on in
                            if on { settings.disabledTools.remove(name) }
                            else { settings.disabledTools.insert(name) }
                        }))
                }
            } header: { Text("Enabled Tools") }
        }
        .formStyle(.grouped)
    }
}

// MARK: Dynamic tools

struct DynamicToolsTab: View {
    @State private var s = DynamicToolSettings.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dynamic Tools")
                .font(.title3.bold())
            Text("Let Aria generate and run code to extend its own capabilities.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)

        Form {
            Section {
                Toggle("Allow Aria to write and run code", isOn: $s.allowCodeExecution)
                Toggle("Show code before running", isOn: $s.showCodeBeforeRun)
                Toggle("Ask before saving new tools", isOn: $s.askBeforeSaving)
                Toggle("Sync community tools", isOn: $s.syncCommunityTools)
            } header: { Text("Execution") }

            Section {
                Text("Generated tools live in Application Support/Aria/tools.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Storage") }
        }
        .formStyle(.grouped)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("On-Device Learning")
                .font(.title3.bold())
            Text("Aria observes your patterns locally to get smarter over time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)

        Form {
            Section {
                Toggle("Learning enabled", isOn: $s.enabled)
                Toggle("Pause all automations", isOn: $s.automationsPaused)
                HStack {
                    Text("Sensitivity")
                    Slider(value: $s.sensitivity, in: 0.6...0.9, step: 0.05)
                    Text(label(for: s.sensitivity)).font(.caption).frame(width: 90, alignment: .trailing)
                }
            } header: { Text("Behavior") }

            Section {
                Text("Conservative requires more confidence before suggesting; Aggressive suggests sooner.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("All learning happens on-device. Nothing is sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("About") }
        }
        .formStyle(.grouped)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Mirror Bridge")
                .font(.title3.bold())
            Text("Stream Aria\u{2019}s context to companion apps on your local network.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)

        Form {
            Section {
                Toggle("Enable Mirror Bridge", isOn: $s.enabled)
                TextField("Port", text: $portText)
                HStack {
                    Circle().fill(s.enabled ? .green : .gray).frame(width: 8, height: 8)
                    Text(s.enabled ? MirrorBridge.ConnectionState.notConnected.rawValue : "Disabled")
                        .foregroundStyle(.secondary)
                }
            } header: { Text("Connection") }

            Section {
                Text("Set-up guide coming soon.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("Help") }
        }
        .formStyle(.grouped)
        .onAppear { portText = String(s.port) }
        .onChange(of: s.enabled) { _, _ in persist() }
        .onChange(of: portText) { _, _ in persist() }
    }

    private func persist() {
        s.port = Int(portText) ?? 8765
        s.save()
    }
}

// MARK: Crew

struct CrewSettingsTab: View {
    private let crew = SubAgentRegistry.crewInfo()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Crew")
                .font(.title3.bold())
            Text("Aria\u{2019}s specialist sub-agents \u{2014} each handles a kind of work.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)

        Form {
            Section {
                ForEach(crew, id: \.name) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.headline)
                        Text(c.persona).font(.caption).foregroundStyle(.secondary)
                        Text(c.description).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Voice

struct VoiceSettingsTab: View {
    @StateObject private var settings = AppSettings.shared
    private let geminiVoices = ["Kore", "Puck", "Charon", "Fenrir", "Aoede", "Leda", "Orus", "Zephyr"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How Aria Speaks")
                .font(.title3.bold())
            Text("Aria speaks with a natural Gemini voice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)

        Form {
            Section {
                Toggle("Speak responses aloud", isOn: $settings.voiceEnabled)
                Picker("Voice", selection: $settings.geminiVoiceName) {
                    ForEach(geminiVoices, id: \.self) { Text($0).tag($0) }
                }
                Text("Aria uses Gemini's natural cloud voice (your Gemini key). If it's momentarily busy she stays quiet for that line — the caption always shows the reply.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Voice") }
        }
        .formStyle(.grouped)
    }
}
