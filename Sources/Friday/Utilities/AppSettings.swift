import Foundation
import Combine
import ServiceManagement

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
    }
}
