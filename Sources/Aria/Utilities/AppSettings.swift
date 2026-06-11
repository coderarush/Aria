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
    @Published var accentChoiceRaw: String { didSet { defaults.set(accentChoiceRaw, forKey: K.accentChoice) } }
    @Published var glowPaletteID: String { didSet { defaults.set(glowPaletteID, forKey: K.glowPaletteID) } }
    @Published var bargeInEnabled: Bool { didSet { defaults.set(bargeInEnabled, forKey: K.bargeInEnabled) } }
    @Published var echoCancellation: Bool { didSet { defaults.set(echoCancellation, forKey: K.echoCancellation) } }
    @Published var bargeInSensitivity: Double { didSet { defaults.set(bargeInSensitivity, forKey: K.bargeInSensitivity) } }
    @Published var conversationSilenceTimeout: Double { didSet { defaults.set(conversationSilenceTimeout, forKey: K.conversationSilenceTimeout) } }
    /// Experimental: only respond to the enrolled owner's voice.
    @Published var speakerVerificationEnabled: Bool { didSet { defaults.set(speakerVerificationEnabled, forKey: K.speakerVerificationEnabled) } }
    /// Use a local Ollama model as a last-resort fallback (offline / all-quota-exhausted).
    @Published var localModelEnabled: Bool { didSet { defaults.set(localModelEnabled, forKey: K.localModelEnabled) } }
    @Published var localModelName: String { didSet { defaults.set(localModelName, forKey: K.localModelName) } }
    /// V9 local-first: prefer the local model for local-eligible task classes
    /// (planning, files, productivity…). Cloud always remains the fallback.
    @Published var localFirstEnabled: Bool { didSet { defaults.set(localFirstEnabled, forKey: K.localFirstEnabled) } }
    /// Run LIVE CONVERSATION on the local model too (experimental — needs a
    /// fast instruct model; thinking models are too slow for voice).
    @Published var localChatEnabled: Bool { didSet { defaults.set(localChatEnabled, forKey: K.localChatEnabled) } }
    /// Speak a short play-by-play line as each autonomous step starts (alive + transparent).
    @Published var spokenStepNarration: Bool { didSet { defaults.set(spokenStepNarration, forKey: K.spokenStepNarration) } }
    /// Soft interaction chimes (wake, task done). Synthesized, AEC-cancelled.
    @Published var uiSoundsEnabled: Bool { didSet { defaults.set(uiSoundsEnabled, forKey: K.uiSoundsEnabled) } }
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
        responseDuration = defaults.object(forKey: K.responseDuration) as? Double ?? 8
        privacyMode = defaults.bool(forKey: K.privacyMode)
        launchAtLogin = defaults.bool(forKey: K.launchAtLogin)
        onboardingComplete = defaults.bool(forKey: K.onboardingComplete)
        disabledTools = Set(defaults.stringArray(forKey: K.disabledTools) ?? [])
        voiceEnabled = defaults.object(forKey: K.voiceEnabled) as? Bool ?? true
        geminiVoiceName = defaults.string(forKey: K.geminiVoiceName) ?? "Kore"
        accentChoiceRaw = defaults.string(forKey: K.accentChoice) ?? "system"
        glowPaletteID = defaults.string(forKey: K.glowPaletteID) ?? "accent"
        // Barge-in + echo cancellation re-enabled (experimental). If AEC ever breaks
        // recognition again, turn it off in Settings → Conversation.
        echoCancellation = defaults.object(forKey: K.echoCancellation) as? Bool ?? true
        bargeInEnabled = defaults.object(forKey: K.bargeInEnabled) as? Bool ?? true
        bargeInSensitivity = defaults.object(forKey: K.bargeInSensitivity) as? Double ?? 0.5
        conversationSilenceTimeout = defaults.object(forKey: K.conversationSilenceTimeout) as? Double ?? 9
        speakerVerificationEnabled = defaults.bool(forKey: K.speakerVerificationEnabled)
        localModelEnabled = defaults.bool(forKey: K.localModelEnabled)
        localModelName = defaults.string(forKey: K.localModelName) ?? "qwen3:8b"
        localFirstEnabled = defaults.object(forKey: K.localFirstEnabled) as? Bool ?? true   // local is the default (V9)
        localChatEnabled = defaults.bool(forKey: K.localChatEnabled)
        spokenStepNarration = defaults.object(forKey: K.spokenStepNarration) as? Bool ?? true
        uiSoundsEnabled = defaults.object(forKey: K.uiSoundsEnabled) as? Bool ?? true
        orbScale = defaults.object(forKey: K.orbScale) as? Double ?? 1.0
        personaStyle = defaults.string(forKey: PersonaStyle.key) ?? "balanced"
        briefingSpoken = defaults.bool(forKey: K.briefingSpoken)
        personaChoice = defaults.string(forKey: K.personaChoice) ?? ""
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
        static let responseDuration = "app.responseDuration"
        static let privacyMode = "app.privacyMode"
        static let launchAtLogin = "app.launchAtLogin"
        static let onboardingComplete = "app.onboardingComplete"
        static let disabledTools = "app.disabledTools"
        static let voiceEnabled = "app.voiceEnabled"
        static let geminiVoiceName = "app.geminiVoiceName"
        static let accentChoice = "app.accentChoice"
        static let glowPaletteID = "app.glowPaletteID"
        static let bargeInEnabled = "app.bargeInEnabled"
        static let echoCancellation = "app.echoCancellation"
        static let bargeInSensitivity = "app.bargeInSensitivity"
        static let conversationSilenceTimeout = "app.conversationSilenceTimeout"
        static let speakerVerificationEnabled = "app.speakerVerificationEnabled"
        static let localModelEnabled = "app.localModelEnabled"
        static let localModelName = "app.localModelName"
        static let localFirstEnabled = "app.localFirst"
        static let localChatEnabled = "app.localChat"
        static let spokenStepNarration = "app.spokenStepNarration"
        static let uiSoundsEnabled = "app.uiSounds"
        static let orbScale = "app.orbScale"
        static let briefingSpoken = "app.briefingSpoken"
        static let personaChoice = "app.personaChoice"
    }
}
