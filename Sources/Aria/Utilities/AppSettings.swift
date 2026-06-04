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
    @Published var voiceIdentifier: String { didSet { defaults.set(voiceIdentifier, forKey: K.voiceIdentifier) } }
    @Published var voiceRate: Double { didSet { defaults.set(voiceRate, forKey: K.voiceRate) } }
    @Published var voiceEngineKind: String { didSet { defaults.set(voiceEngineKind, forKey: K.voiceEngineKind) } }
    @Published var geminiVoiceName: String { didSet { defaults.set(geminiVoiceName, forKey: K.geminiVoiceName) } }
    @Published var accentChoiceRaw: String { didSet { defaults.set(accentChoiceRaw, forKey: K.accentChoice) } }
    @Published var glowPaletteID: String { didSet { defaults.set(glowPaletteID, forKey: K.glowPaletteID) } }
    @Published var bargeInEnabled: Bool { didSet { defaults.set(bargeInEnabled, forKey: K.bargeInEnabled) } }
    @Published var echoCancellation: Bool { didSet { defaults.set(echoCancellation, forKey: K.echoCancellation) } }
    @Published var bargeInSensitivity: Double { didSet { defaults.set(bargeInSensitivity, forKey: K.bargeInSensitivity) } }
    @Published var conversationSilenceTimeout: Double { didSet { defaults.set(conversationSilenceTimeout, forKey: K.conversationSilenceTimeout) } }

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
        voiceIdentifier = defaults.string(forKey: K.voiceIdentifier) ?? ""
        voiceRate = defaults.object(forKey: K.voiceRate) as? Double ?? 0.5
        voiceEngineKind = defaults.string(forKey: K.voiceEngineKind) ?? "apple"
        geminiVoiceName = defaults.string(forKey: K.geminiVoiceName) ?? "Kore"
        accentChoiceRaw = defaults.string(forKey: K.accentChoice) ?? "system"
        glowPaletteID = defaults.string(forKey: K.glowPaletteID) ?? "accent"
        // Barge-in + echo cancellation re-enabled (experimental). If AEC ever breaks
        // recognition again, turn it off in Settings → Conversation.
        echoCancellation = defaults.object(forKey: K.echoCancellation) as? Bool ?? true
        bargeInEnabled = defaults.object(forKey: K.bargeInEnabled) as? Bool ?? true
        bargeInSensitivity = defaults.object(forKey: K.bargeInSensitivity) as? Double ?? 0.5
        conversationSilenceTimeout = defaults.object(forKey: K.conversationSilenceTimeout) as? Double ?? 9
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
        static let voiceIdentifier = "app.voiceIdentifier"
        static let voiceRate = "app.voiceRate"
        static let voiceEngineKind = "app.voiceEngineKind"
        static let geminiVoiceName = "app.geminiVoiceName"
        static let accentChoice = "app.accentChoice"
        static let glowPaletteID = "app.glowPaletteID"
        static let bargeInEnabled = "app.bargeInEnabled"
        static let echoCancellation = "app.echoCancellation"
        static let bargeInSensitivity = "app.bargeInSensitivity"
        static let conversationSilenceTimeout = "app.conversationSilenceTimeout"
    }
}
