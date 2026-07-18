import Foundation
import Combine
import ServiceManagement
import SwiftUI

/// General app preferences (orb, privacy, onboarding), persisted in UserDefaults
/// and observable by SwiftUI settings views.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum OrbPosition: String, CaseIterable, Identifiable {
        case bottomCenter, bottomRight, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .bottomCenter: return "Bottom Center"
            case .bottomRight: return "Bottom Right"
            case .custom: return "Custom"
            }
        }
    }

    enum OrbSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var diameter: CGFloat {
            switch self { case .small: return 64; case .medium: return 84; case .large: return 108 }
        }
    }

    @Published var orbPosition: OrbPosition {
        didSet { defaults.set(orbPosition.rawValue, forKey: K.orbPosition) }
    }
    @Published var orbSize: OrbSize {
        didSet { defaults.set(orbSize.rawValue, forKey: K.orbSize) }
    }
    /// Keep the resting companion available between turns.
    @Published var idleBlobVisible: Bool { didSet { defaults.set(idleBlobVisible, forKey: K.idleBlobVisible) } }
    @Published var responseDuration: Double {
        didSet { defaults.set(responseDuration, forKey: K.responseDuration) }
    }
    @Published var privacyMode: Bool {
        didSet { defaults.set(privacyMode, forKey: K.privacyMode) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: K.launchAtLogin)
            Self.applyLaunchAtLogin(launchAtLogin)
        }
    }
    @Published var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: K.onboardingComplete) }
    }
    /// Tool names the user has explicitly disabled.
    @Published var disabledTools: Set<String> {
        didSet { defaults.set(Array(disabledTools), forKey: K.disabledTools) }
    }
    @Published var voiceEnabled: Bool { didSet { defaults.set(voiceEnabled, forKey: K.voiceEnabled) } }
    @Published var geminiVoiceName: String { didSet { defaults.set(geminiVoiceName, forKey: K.geminiVoiceName) } }
    /// TTS engine (VoiceEngine.TTSEngine raw value): edge | gemini | elevenlabs | apple.
    /// Default "edge" — free, keyless, unlimited neural voices.
    @Published var ttsEngine: String { didSet { defaults.set(ttsEngine, forKey: K.ttsEngine) } }
    /// Selected Edge neural voice id (e.g. en-US-AndrewMultilingualNeural).
    @Published var edgeVoiceName: String { didSet { defaults.set(edgeVoiceName, forKey: K.edgeVoiceName) } }
    /// Selected ElevenLabs voice id.
    @Published var elevenLabsVoiceID: String { didSet { defaults.set(elevenLabsVoiceID, forKey: K.elevenLabsVoiceID) } }
    /// Instant commands: run everyday one-shots (open app, volume, timer, URL)
    /// with zero model calls for near-instant response. Default on.
    @Published var instantCommandsEnabled: Bool { didSet { defaults.set(instantCommandsEnabled, forKey: K.instantCommandsEnabled) } }
    /// Autonomous mode skips "Approve?" prompts for attended commands and lets
    /// Aria act on high-confidence anticipations. Background runs still fail
    /// closed for important irreversible actions, and this is off by default.
    @Published var autonomousMode: Bool { didSet { defaults.set(autonomousMode, forKey: K.autonomousMode) } }
    @Published var accentChoiceRaw: String { didSet { defaults.set(accentChoiceRaw, forKey: K.accentChoice) } }
    @Published var glowPaletteID: String { didSet { defaults.set(glowPaletteID, forKey: K.glowPaletteID) } }
    @Published var bargeInEnabled: Bool { didSet { defaults.set(bargeInEnabled, forKey: K.bargeInEnabled) } }
    @Published var echoCancellation: Bool { didSet { defaults.set(echoCancellation, forKey: K.echoCancellation) } }
    @Published var bargeInSensitivity: Double { didSet { defaults.set(bargeInSensitivity, forKey: K.bargeInSensitivity) } }
    @Published var conversationSilenceTimeout: Double { didSet { defaults.set(conversationSilenceTimeout, forKey: K.conversationSilenceTimeout) } }
    /// Experimental: only respond to the enrolled owner's voice.
    @Published var speakerVerificationEnabled: Bool { didSet { defaults.set(speakerVerificationEnabled, forKey: K.speakerVerificationEnabled) } }
    /// Unix timestamp (timeIntervalSince1970) when the owner's voiceprint enrollment
    /// completed. 0.0 means never enrolled. Used by SpeakerGracePolicy.
    @Published var speakerVerificationEnrolledDate: Double {
        didSet { defaults.set(speakerVerificationEnrolledDate, forKey: K.speakerVerificationEnrolledDate) }
    }
    /// Use a local Ollama model as a last-resort fallback (offline / all-quota-exhausted).
    @Published var localModelEnabled: Bool { didSet { defaults.set(localModelEnabled, forKey: K.localModelEnabled) } }
    @Published var localModelName: String { didSet { defaults.set(localModelName, forKey: K.localModelName) } }
    /// Local vision model (llava / qwen2.5vl / moondream) for on-device screen
    /// understanding — the Lens + computer-use targeting. Empty ⇒ vision uses
    /// cloud (Gemini). Read by `VisionRouter` (key `app.localVisionModel`).
    @Published var localVisionModel: String { didSet { defaults.set(localVisionModel, forKey: K.localVisionModel) } }
    /// V9 local-first: prefer the local model for local-eligible task classes
    /// (planning, files, productivity…). Cloud always remains the fallback.
    @Published var localFirstEnabled: Bool { didSet { defaults.set(localFirstEnabled, forKey: K.localFirstEnabled) } }
    /// Run LIVE CONVERSATION on the local model too (experimental — needs a
    /// fast instruct model; thinking models are too slow for voice).
    @Published var localChatEnabled: Bool { didSet { defaults.set(localChatEnabled, forKey: K.localChatEnabled) } }
    /// Speak a short play-by-play line as each autonomous step starts (alive + transparent).
    @Published var spokenStepNarration: Bool { didSet { defaults.set(spokenStepNarration, forKey: K.spokenStepNarration) } }
    /// Whether the HUD blob splits into orbiting blobs while thinking (default on).
    /// Off → the calmer shimmer ring only, for users who prefer less ambient motion.
    @Published var expressiveThinking: Bool { didSet { defaults.set(expressiveThinking, forKey: K.expressiveThinking) } }
    /// Soft interaction chimes (wake, task done). Synthesized, AEC-cancelled.
    @Published var uiSoundsEnabled: Bool { didSet { defaults.set(uiSoundsEnabled, forKey: K.uiSoundsEnabled) } }
    /// Sonic voicing for the interaction chimes (SoundTheme raw value).
    @Published var soundTheme: String { didSet { defaults.set(soundTheme, forKey: SoundTheme.key) } }
    /// Preferred offline TTS voice identifier ("" = best installed, automatic).
    @Published var localVoiceID: String { didSet { defaults.set(localVoiceID, forKey: LocalVoice.key) } }
    /// Standing instructions honored in every conversation (CustomInstructions).
    @Published var customInstructions: String {
        didSet { defaults.set(customInstructions, forKey: CustomInstructions.key) }
    }
    /// Orb size multiplier (0.7 small … 1.3 large).
    @Published var orbScale: Double { didSet { defaults.set(orbScale, forKey: K.orbScale) } }
    /// Personality flavor (PersonaStyle raw value).
    @Published var personaStyle: String { didSet { defaults.set(personaStyle, forKey: PersonaStyle.key) } }
    /// Speak the scheduled daily briefing aloud when it lands (V11 P4).
    /// On-demand "brief me" always speaks; this governs the background agent.
    @Published var briefingSpoken: Bool { didSet { defaults.set(briefingSpoken, forKey: K.briefingSpoken) } }
    /// V11 FRE: the persona picked at first run ("Student"/"Developer"/"Founder").
    /// Informs the installed pack and the default focus-mode preset.
    @Published var personaChoice: String { didSet { defaults.set(personaChoice, forKey: K.personaChoice) } }
    /// V11.0.1: where the blob consolidates, as a normalized screen point
    /// (0…1, origin top-left). `nil` = fall back to `orbPosition` alignment.
    /// Set by dragging the blob; she reappears here next time she speaks.
    @Published var orbAnchor: CGPoint? {
        didSet {
            if let a = orbAnchor {
                defaults.set(Double(a.x), forKey: K.orbAnchorX)
                defaults.set(Double(a.y), forKey: K.orbAnchorY)
            } else {
                defaults.removeObject(forKey: K.orbAnchorX)
                defaults.removeObject(forKey: K.orbAnchorY)
            }
        }
    }

    /// Forget the dragged anchor and return to the `orbPosition` default.
    func clearOrbAnchor() { orbAnchor = nil }

    /// V11.0.1: opt-in Mac-wide personal context (recent files + upcoming events).
    /// Same UserDefaults key the PersonalContextEngine reads, so they stay in sync.
    @Published var personalContextEnabled: Bool {
        didSet { defaults.set(personalContextEnabled, forKey: K.personalContextEnabled) }
    }
    /// System-wide dictation (⌥⇧D): talk → cleaned text typed into the focused app.
    @Published var dictationEnabled: Bool {
        didSet { defaults.set(dictationEnabled, forKey: K.dictationEnabled) }
    }
    /// V11.1.1 Phase C: opt-in on-device model of the user (people/projects she
    /// refers to + writing-style profile). Same key the EntityStore reads.
    @Published var personalizationEnabled: Bool {
        didSet {
            defaults.set(personalizationEnabled, forKey: K.personalizationEnabled)
            // Seed the writing-style profile from the user's sent mail the moment
            // they opt in (best-effort; no-op if Google isn't connected).
            if personalizationEnabled { Task { await StyleLearner.shared.refreshFromSentMail() } }
        }
    }
    /// V11.1.1: how connectors authenticate — "byo" (bring your own OAuth client ID,
    /// the working default until the hosted relay is deployed) or "relay" (hosted,
    /// no client ID needed — switch to this once the relay is live). Connector layer reads it.
    @Published var connectorMode: String {
        didSet { defaults.set(connectorMode, forKey: K.connectorMode) }
    }
    /// V11.1.1 Phase D: let Aria ACT on her own very-high-confidence, reversible
    /// anticipations (receipted + undoable) instead of only suggesting. Opt-in —
    /// it's the boldest autonomy, so the user turns it on deliberately.
    @Published var autonomousActions: Bool {
        didSet { defaults.set(autonomousActions, forKey: K.autonomousActions) }
    }
    /// Optional AI cleanup pass on dictated text (fixes punctuation / mis-hears at
    /// the cost of a round-trip). Off by default — heuristic cleanup is instant.
    @Published var dictationAICleanup: Bool {
        didSet { defaults.set(dictationAICleanup, forKey: K.dictationAICleanup) }
    }

    var accentChoice: AccentChoice {
        get { Theme.decodeChoice(accentChoiceRaw) }
        set { accentChoiceRaw = Theme.encode(newValue) }
    }
    var accentColor: Color { Theme.color(for: accentChoice) }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        orbPosition = OrbPosition(rawValue: defaults.string(forKey: K.orbPosition) ?? "") ?? .bottomCenter
        orbSize = OrbSize(rawValue: defaults.string(forKey: K.orbSize) ?? "") ?? .medium
        idleBlobVisible = defaults.object(forKey: K.idleBlobVisible) as? Bool ?? true
        responseDuration = defaults.object(forKey: K.responseDuration) as? Double ?? 8
        privacyMode = defaults.bool(forKey: K.privacyMode)
        launchAtLogin = defaults.bool(forKey: K.launchAtLogin)
        onboardingComplete = defaults.bool(forKey: K.onboardingComplete)
        disabledTools = Set(defaults.stringArray(forKey: K.disabledTools) ?? [])
        voiceEnabled = defaults.object(forKey: K.voiceEnabled) as? Bool ?? true
        geminiVoiceName = defaults.string(forKey: K.geminiVoiceName) ?? "Kore"
        ttsEngine = defaults.string(forKey: K.ttsEngine) ?? "edge"
        edgeVoiceName = defaults.string(forKey: K.edgeVoiceName) ?? EdgeTTS.defaultVoice
        elevenLabsVoiceID = defaults.string(forKey: K.elevenLabsVoiceID) ?? ElevenLabsTTS.defaultVoiceID
        accentChoiceRaw = defaults.string(forKey: K.accentChoice) ?? "system"
        glowPaletteID = defaults.string(forKey: K.glowPaletteID) ?? "accent"
        // Barge-in + echo cancellation re-enabled (experimental). If AEC ever breaks
        // recognition again, turn it off in Settings → Conversation.
        echoCancellation = defaults.object(forKey: K.echoCancellation) as? Bool ?? true
        bargeInEnabled = defaults.object(forKey: K.bargeInEnabled) as? Bool ?? true
        bargeInSensitivity = defaults.object(forKey: K.bargeInSensitivity) as? Double ?? 0.35
        conversationSilenceTimeout = defaults.object(forKey: K.conversationSilenceTimeout) as? Double ?? 9
        speakerVerificationEnabled = defaults.bool(forKey: K.speakerVerificationEnabled)
        speakerVerificationEnrolledDate = defaults.object(forKey: K.speakerVerificationEnrolledDate) as? Double ?? 0.0
        localModelEnabled = defaults.bool(forKey: K.localModelEnabled)
        localModelName = defaults.string(forKey: K.localModelName) ?? "qwen3:8b"
        localVisionModel = defaults.string(forKey: K.localVisionModel) ?? ""
        localFirstEnabled = defaults.object(forKey: K.localFirstEnabled) as? Bool ?? true   // local is the default (V9)
        // Local-first voice ON by default: only actually routes local when a local
        // model server is alive (else it transparently falls back to fast cloud).
        localChatEnabled = defaults.object(forKey: K.localChatEnabled) as? Bool ?? true
        spokenStepNarration = defaults.object(forKey: K.spokenStepNarration) as? Bool ?? true
        expressiveThinking = defaults.object(forKey: K.expressiveThinking) as? Bool ?? true
        uiSoundsEnabled = defaults.object(forKey: K.uiSoundsEnabled) as? Bool ?? true
        soundTheme = defaults.string(forKey: SoundTheme.key) ?? SoundTheme.aurora.rawValue
        localVoiceID = defaults.string(forKey: LocalVoice.key) ?? ""
        instantCommandsEnabled = defaults.object(forKey: K.instantCommandsEnabled) as? Bool ?? true
        autonomousMode = defaults.object(forKey: K.autonomousMode) as? Bool ?? false
        customInstructions = defaults.string(forKey: CustomInstructions.key) ?? ""
        orbScale = defaults.object(forKey: K.orbScale) as? Double ?? 1.0
        personaStyle = defaults.string(forKey: PersonaStyle.key) ?? "balanced"
        briefingSpoken = defaults.bool(forKey: K.briefingSpoken)
        personaChoice = defaults.string(forKey: K.personaChoice) ?? ""
        orbAnchor = (defaults.object(forKey: K.orbAnchorX) as? Double).flatMap { x in
            (defaults.object(forKey: K.orbAnchorY) as? Double).map { CGPoint(x: x, y: $0) }
        }
        personalContextEnabled = defaults.bool(forKey: K.personalContextEnabled)
        dictationEnabled = defaults.object(forKey: K.dictationEnabled) as? Bool ?? true
        dictationAICleanup = defaults.bool(forKey: K.dictationAICleanup)
        autonomousActions = defaults.bool(forKey: K.autonomousActions)
        personalizationEnabled = defaults.bool(forKey: K.personalizationEnabled)
        // Raw values MUST match Core/Connectors ConnectorMode (.bringYourOwn/.relay).
        connectorMode = defaults.string(forKey: K.connectorMode) ?? "bringYourOwn"
        // Pin the working default so the connector layer reads a concrete mode
        // (relay isn't deployed yet — bring-your-own is what actually connects today).
        if defaults.string(forKey: K.connectorMode) == nil {
            defaults.set("bringYourOwn", forKey: K.connectorMode)
        }
    }

    /// Register/unregister the app as a login item (SMAppService, macOS 13+).
    static func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            Log.app.error("Launch-at-login update failed: \(error.localizedDescription)")
        }
    }

    private enum K {
        static let orbPosition = "app.orbPosition"
        static let orbSize = "app.orbSize"
        static let idleBlobVisible = "app.idleBlobVisible"
        static let responseDuration = "app.responseDuration"
        static let privacyMode = "app.privacyMode"
        static let launchAtLogin = "app.launchAtLogin"
        static let onboardingComplete = "app.onboardingComplete"
        static let disabledTools = "app.disabledTools"
        static let voiceEnabled = "app.voiceEnabled"
        static let geminiVoiceName = "app.geminiVoiceName"
        static let ttsEngine = "app.ttsEngine"
        static let edgeVoiceName = "app.edgeVoiceName"
        static let elevenLabsVoiceID = "app.elevenLabsVoiceID"
        static let instantCommandsEnabled = "app.instantCommands"
        static let autonomousMode = "app.autonomousMode"
        static let accentChoice = "app.accentChoice"
        static let glowPaletteID = "app.glowPaletteID"
        static let bargeInEnabled = "app.bargeInEnabled"
        static let echoCancellation = "app.echoCancellation"
        static let bargeInSensitivity = "app.bargeInSensitivity"
        static let conversationSilenceTimeout = "app.conversationSilenceTimeout"
        static let speakerVerificationEnabled = "app.speakerVerificationEnabled"
        static let speakerVerificationEnrolledDate = "app.speakerVerificationEnrolledDate"
        static let localModelEnabled = "app.localModelEnabled"
        static let localModelName = "app.localModelName"
        static let localVisionModel = "app.localVisionModel"
        static let localFirstEnabled = "app.localFirst"
        static let localChatEnabled = "app.localChat"
        static let spokenStepNarration = "app.spokenStepNarration"
        static let expressiveThinking = "app.expressiveThinking"
        static let uiSoundsEnabled = "app.uiSounds"
        static let orbScale = "app.orbScale"
        static let briefingSpoken = "app.briefingSpoken"
        static let personaChoice = "app.personaChoice"
        static let orbAnchorX = "app.orbAnchorX"
        static let orbAnchorY = "app.orbAnchorY"
        static let personalContextEnabled = "app.personalContextEnabled"
        static let dictationEnabled = "app.dictationEnabled"
        static let dictationAICleanup = "app.dictationAICleanup"
        static let autonomousActions = "app.autonomousActions"
        static let personalizationEnabled = "app.personalizationEnabled"
        static let connectorMode = "app.connectorMode"
    }
}
