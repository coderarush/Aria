import SwiftUI

/// Crash-safe stand-ins for Form/Section. On macOS 26, SwiftUI's Form/List build a lazy
/// DynamicViewList whose row evaluation calls swift_task_isCurrentExecutorWithFlags and
/// crashes with EXC_BAD_ACCESS (the executor-isolation check dereferences a bad ref). These
/// are plain, eager VStacks — same grouped look, but no List under the hood, so the body
/// builds on the main actor and never trips the check.
private struct SForm<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SSection<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title {
                Text(title).font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary).textCase(.uppercase)
            }
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
        }
    }
}

/// A tab heading (title + subtitle).
private struct TabHead: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4).padding(.bottom, 8)
    }
}

/// Aria's settings window — plain sidebar + scrolling detail. Deliberately no
/// NavigationSplitView / List / Form anywhere (see SForm above for why).
struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general = "General", voice = "Voice", conversation = "Conversation",
             proactive = "Proactive",
             apiKey = "API Key", memory = "Memory", activity = "Activity", tools = "Tools", dynamic = "Dynamic", brain = "Brain", mirror = "Mirror", crew = "Crew", license = "License"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general:      return "gearshape"
            case .voice:        return "speaker.wave.2"
            case .conversation: return "bubble.left.and.bubble.right"
            case .proactive:    return "bell.badge"
            case .apiKey:       return "key"
            case .memory:       return "brain.head.profile"
            case .activity:     return "list.bullet.rectangle"
            case .tools:        return "wrench.and.screwdriver"
            case .dynamic:      return "sparkles"
            case .brain:        return "brain"
            case .mirror:       return "rectangle.on.rectangle"
            case .crew:         return "person.3"
            case .license:      return "checkmark.seal"
            }
        }
    }

    @State private var selection: Section = .general

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Section.allCases) { section in
                        Button {
                            selection = section
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: section.icon).frame(width: 18)
                                Text(section.rawValue)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(selection == section ? Color.accentColor.opacity(0.18) : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .frame(width: 190)

            Divider()

            ScrollView {
                detailView
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 500)
    }

    @ViewBuilder private var detailView: some View {
        switch selection {
        case .general:      GeneralSettingsTab()
        case .voice:        VoiceSettingsTab()
        case .conversation: ConversationSettingsTab()
        case .proactive:    ProactiveSettingsTab()
        case .apiKey:       APIKeyTab()
        case .memory:       MemorySettingsTab()
        case .activity:     ActivityTab()
        case .tools:        ToolsTab()
        case .dynamic:      DynamicToolsTab()
        case .brain:        BrainTab()
        case .mirror:       MirrorTab()
        case .crew:         CrewSettingsTab()
        case .license:      LicenseTab()
        }
    }
}

// MARK: License

struct LicenseTab: View {
    @StateObject private var lic = LicenseManager.shared
    @State private var key = ""
    @State private var msg = ""
    @State private var busy = false

    private var statusText: String {
        switch lic.status {
        case .licensed: return "Licensed"
        case .trial(let d): return "Trial — \(d) day\(d == 1 ? "" : "s") left"
        case .expired: return "Trial expired"
        }
    }
    private var statusColor: Color {
        switch lic.status { case .licensed: return .green; case .trial: return .secondary; case .expired: return .orange }
    }

    var body: some View {
        TabHead(title: "License", subtitle: "One purchase, kept forever. Activate the key from your receipt.")
        SForm {
            SSection {
                HStack { Text("Status"); Spacer(); Text(statusText).foregroundStyle(statusColor) }
            }
            if !lic.isLicensed {
                SSection("Activate") {
                    TextField("License key", text: $key)
                    HStack {
                        Button(busy ? "Activating\u{2026}" : "Activate") { activate() }
                            .buttonStyle(.borderedProminent).disabled(busy || key.isEmpty)
                        Link("Buy a license", destination: URL(string: "https://github.com/coderarush/Aria")!)
                    }
                    if !msg.isEmpty { Text(msg).font(.caption).foregroundStyle(.secondary) }
                }
            } else {
                SSection {
                    Button("Deactivate on this Mac", role: .destructive) { lic.deactivate(); msg = "" }
                }
            }
        }
    }

    private func activate() {
        busy = true; msg = ""
        Task { let r = await lic.activate(key: key); msg = r.message; busy = false }
    }
}

// MARK: General

struct GeneralSettingsTab: View {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var updater = UpdateChecker.shared

    var body: some View {
        TabHead(title: "Appearance & Behavior", subtitle: "Customize Aria\u{2019}s look and runtime behavior.")
        SForm {
            SSection("Accent Color") {
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
            }

            SSection("Updates") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(updater.currentVersion).foregroundStyle(.secondary).monospacedDigit()
                }
                if let v = updater.newVersion, let url = updater.releaseURL {
                    HStack {
                        Label("Version \(v) is available", systemImage: "arrow.down.circle.fill").foregroundStyle(.green)
                        Spacer()
                        Link("Download", destination: url)
                    }
                } else {
                    Button(updater.checking ? "Checking\u{2026}" : "Check for updates") {
                        Task { await updater.check() }
                    }.disabled(updater.checking)
                }
            }

            SSection("Behavior") {
                HStack {
                    Text("Response duration")
                    Slider(value: $settings.responseDuration, in: 3...20, step: 1)
                    Text("\(Int(settings.responseDuration))s").monospacedDigit()
                }
                Toggle("Privacy mode (disable screen capture)", isOn: $settings.privacyMode)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
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
        TabHead(title: "Conversation", subtitle: "How Aria listens and lets you interrupt.")
        SForm {
            SSection {
                HStack {
                    Text("End conversation after silence")
                    Slider(value: $settings.conversationSilenceTimeout, in: 5...20, step: 1)
                    Text("\(Int(settings.conversationSilenceTimeout))s").monospacedDigit()
                }
                Text("Talk to Aria in a continuous back-and-forth — after she answers, just speak your next question (no need to say “Hey Aria” again). She stops listening after this much silence.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SSection("Barge-in") {
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
            }

            SSection("Play-by-play") {
                Toggle("Narrate steps aloud", isOn: $settings.spokenStepNarration)
                Text("During a multi-step task, Aria says a short play-by-play as she works (“Searching the web…”, “Saving your note…”). Turn off to keep her quiet between the plan and the result.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SSection("Speaker verification") {
                Toggle("Only respond to my voice", isOn: $settings.speakerVerificationEnabled)
                Button("Teach Aria my voice") { NotificationCenter.default.post(name: .ariaEnrollVoice, object: nil) }
                Text("Experimental. After enabling, click “Teach Aria my voice”, then say “Hey Aria” a few times. She'll bias toward your voice and ignore others. Basic on-device voiceprint — not a hard security guarantee.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SSection("Computer use") {
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
            }
        }
        .onAppear { axOK = AXReader.hasPermission }
    }
}

// MARK: Proactive (v9)

struct ProactiveSettingsTab: View {
    @State private var s = ProactiveSettings.load()

    var body: some View {
        TabHead(title: "Proactive Presence", subtitle: "Aria anticipates and gently offers \u{2014} before you ask.")
        SForm {
            SSection("Anticipation") {
                Toggle("Let Aria be proactive", isOn: $s.enabled)
            }

            if s.enabled {
                SSection("What she watches") {
                    sourceToggle("Calendar & time", .calendar,
                                 "A quiet heads-up just before your meetings.")
                    sourceToggle("Learned routines", .routine,
                                 "Offer to automate habits she notices on-device.")
                    Text("More signals (recurring commands, on-screen context) are coming.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                SSection("Quiet hours") {
                    Toggle("Stay silent during quiet hours", isOn: $s.quietHoursEnabled)
                    if s.quietHoursEnabled {
                        HStack(spacing: 16) {
                            Stepper("From \(s.quietHours.startHour):00",
                                    value: $s.quietHours.startHour, in: 0...23)
                            Stepper("to \(s.quietHours.endHour):00",
                                    value: $s.quietHours.endHour, in: 0...23)
                        }
                        Text("Only time-critical reminders (a meeting about to start) come through.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            SSection("How it feels") {
                Text("When Aria has something, the orb glows quietly \u{2014} she speaks it only when you wake her or glance over. Say \u{201C}yes\u{201D} to do it, or just ignore it and it fades.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: s.enabled) { _, _ in s.save() }
        .onChange(of: s.quietHoursEnabled) { _, _ in s.save() }
        .onChange(of: s.quietHours.startHour) { _, _ in s.save() }
        .onChange(of: s.quietHours.endHour) { _, _ in s.save() }
    }

    private func sourceToggle(_ title: String, _ source: SuggestionSource, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: Binding(
                get: { s.isSourceEnabled(source) },
                set: { s.sourceEnabled[source] = $0; s.save() }))
            Text(help).font(.caption2).foregroundStyle(.tertiary)
        }
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
        TabHead(title: "Your Gemini Keys", subtitle: "Stored securely in the macOS Keychain. Never transmitted by Aria.")
        SForm {
            SSection("API Keys") {
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
            }

            SSection("More free quota") {
                Text("Get free keys at aistudio.google.com. Each Google project has its own free daily quota, so adding 2–3 keys from different projects multiplies how much you can do for free.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SSection("Free fallback providers") {
                SecureField("Groq key (groq.com — free, fast)", text: $groq)
                SecureField("Cerebras key (cerebras.ai — free, fast)", text: $cerebras)
                SecureField("OpenRouter key (openrouter.ai — free tier)", text: $openRouter)
                Text("When your Gemini quota runs out, Aria automatically continues on these free, fast providers — so she keeps working. Each is free to sign up; add any you like, then Save.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SSection("Local model") {
                Toggle("Use a local model when everything else is out (Ollama)", isOn: $settings.localModelEnabled)
                Toggle("Local-first: prefer the local model for everyday tasks", isOn: $settings.localFirstEnabled)
                if settings.localModelEnabled || settings.localFirstEnabled {
                    TextField("Ollama model", text: $settings.localModelName)
                }
                if settings.localFirstEnabled {
                    Text("Planning, files, calendar, notes and similar tasks run on your Mac first — private, fast, no quota. Research, complex reasoning and conversation stay on the cloud model, and anything the local model can't handle falls back automatically. Requires Ollama (ollama.com) with the model pulled — Qwen 3 8B recommended.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if settings.localModelEnabled {
                    Text("Last resort — works offline. Requires Ollama running (ollama.com) with the model pulled. Slower, but never hits a limit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
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
        TabHead(title: "What Aria Remembers", subtitle: "Durable facts Aria recalls across sessions. Say “remember that …” to add one.")
        SForm {
            SSection("Memories (\(facts.count))") {
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
                        Divider()
                    }
                }
            }

            if !facts.isEmpty {
                SSection {
                    Button("Forget everything", role: .destructive) {
                        Task { await LongTermMemory.shared.clear(); await reload() }
                    }
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        facts = await LongTermMemory.shared.all().sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: Activity

struct ActivityTab: View {
    @State private var entries: [ActivityEntry] = []

    var body: some View {
        TabHead(title: "Activity", subtitle: "A traceable log of every action Aria has taken. Newest first.")
        SForm {
            SSection("Recent actions (\(entries.count))") {
                if entries.isEmpty {
                    Text("No actions recorded yet.").foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(entries) { e in
                        HStack(alignment: .top, spacing: 9) {
                            Circle().fill(color(for: e.outcome)).frame(width: 8, height: 8).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(e.tool).font(.system(size: 13, weight: .semibold))
                                    if !e.detail.isEmpty {
                                        Text(e.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                if !e.summary.isEmpty {
                                    Text(e.summary).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                                }
                                Text(e.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                            Text(e.outcome.rawValue).font(.caption2).foregroundStyle(color(for: e.outcome))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if e.id != entries.last?.id { Divider() }
                    }
                }
            }
            if !entries.isEmpty {
                SSection {
                    Button("Clear activity log", role: .destructive) {
                        Task { await ActivityLog.shared.clear(); await reload() }
                    }
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async { entries = await ActivityLog.shared.recent(100) }

    private func color(for outcome: ActivityEntry.Outcome) -> Color {
        switch outcome {
        case .ok:       return .green
        case .failed:   return .orange
        case .declined: return .secondary
        }
    }
}

// MARK: Tools

struct ToolsTab: View {
    @StateObject private var settings = AppSettings.shared
    private let toolNames = ToolRegistry.builtins().map { type(of: $0).name }.sorted()

    var body: some View {
        TabHead(title: "Tool Permissions", subtitle: "Choose which built-in tools Aria can use on your behalf.")
        SForm {
            SSection("Enabled Tools") {
                ForEach(toolNames, id: \.self) { name in
                    Toggle(name, isOn: Binding(
                        get: { !settings.disabledTools.contains(name) },
                        set: { on in
                            if on { settings.disabledTools.remove(name) }
                            else { settings.disabledTools.insert(name) }
                        }))
                }
            }
        }
    }
}

// MARK: Dynamic tools

struct DynamicToolsTab: View {
    @State private var s = DynamicToolSettings.load()

    var body: some View {
        TabHead(title: "Dynamic Tools", subtitle: "Let Aria generate and run code to extend its own capabilities.")
        SForm {
            SSection("Execution") {
                Toggle("Allow Aria to write and run code", isOn: $s.allowCodeExecution)
                Toggle("Show code before running", isOn: $s.showCodeBeforeRun)
                Toggle("Ask before saving new tools", isOn: $s.askBeforeSaving)
                Toggle("Sync community tools", isOn: $s.syncCommunityTools)
            }
            SSection("Storage") {
                Text("Generated tools live in Application Support/Aria/tools.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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
        TabHead(title: "On-Device Learning", subtitle: "Aria observes your patterns locally to get smarter over time.")
        SForm {
            SSection("Behavior") {
                Toggle("Learning enabled", isOn: $s.enabled)
                Toggle("Pause all automations", isOn: $s.automationsPaused)
                HStack {
                    Text("Sensitivity")
                    Slider(value: $s.sensitivity, in: 0.6...0.9, step: 0.05)
                    Text(label(for: s.sensitivity)).font(.caption).frame(width: 90, alignment: .trailing)
                }
            }
            SSection("About") {
                Text("Conservative requires more confidence before suggesting; Aggressive suggests sooner.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("All learning happens on-device. Nothing is sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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
        TabHead(title: "Mirror Bridge", subtitle: "Stream Aria\u{2019}s context to companion apps on your local network.")
        SForm {
            SSection("Connection") {
                Toggle("Enable Mirror Bridge", isOn: $s.enabled)
                TextField("Port", text: $portText)
                HStack {
                    Circle().fill(s.enabled ? .green : .gray).frame(width: 8, height: 8)
                    Text(s.enabled ? MirrorBridge.ConnectionState.notConnected.rawValue : "Disabled")
                        .foregroundStyle(.secondary)
                }
            }
            SSection("Help") {
                Text("Set-up guide coming soon.").font(.caption).foregroundStyle(.secondary)
            }
        }
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
        TabHead(title: "Crew", subtitle: "Aria\u{2019}s specialist sub-agents \u{2014} each handles a kind of work.")
        SForm {
            SSection {
                ForEach(crew, id: \.name) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.headline)
                        Text(c.persona).font(.caption).foregroundStyle(.secondary)
                        Text(c.description).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                    if c.name != crew.last?.name { Divider() }
                }
            }
        }
    }
}

// MARK: Voice

struct VoiceSettingsTab: View {
    @StateObject private var settings = AppSettings.shared
    private let geminiVoices = ["Kore", "Puck", "Charon", "Fenrir", "Aoede", "Leda", "Orus", "Zephyr"]

    var body: some View {
        TabHead(title: "How Aria Speaks", subtitle: "Aria speaks with a natural Gemini voice.")
        SForm {
            SSection("Voice") {
                Toggle("Speak responses aloud", isOn: $settings.voiceEnabled)
                Picker("Voice", selection: $settings.geminiVoiceName) {
                    ForEach(geminiVoices, id: \.self) { Text($0).tag($0) }
                }
                Text("Aria uses Gemini's natural cloud voice (your Gemini key). If it's momentarily busy she stays quiet for that line — the caption always shows the reply.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
