import Foundation

extension Notification.Name {
    /// Posted by Settings to start owner-voice enrollment.
    static let ariaEnrollVoice = Notification.Name("AriaEnrollVoice")
}

/// Optional "only respond to my voice" gate. EXPERIMENTAL and OFF by default — it
/// uses a basic band-energy voiceprint (`VoiceFeatures`/`SpeakerVerifier`), not a
/// trained speaker-embedding model, so it biases toward the owner rather than being a
/// hard security boundary. Single entry point `accept(_:)`; when disabled or not
/// enrolled it always allows, so the wake path is unaffected by default.
@MainActor
final class SpeakerGate {
    private var profile: [Float] = []
    private var enrolling: [[Float]] = []
    private var isEnrolling = false
    private let needed = 3
    private let threshold: Float = 0.80
    private let fileURL: URL

    var enabled = false
    var isEnrolled: Bool { !profile.isEmpty }
    /// Fired (on the main actor) when enrollment finishes capturing `needed` samples.
    var onEnrollmentComplete: (() -> Void)?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.profile = Self.load(from: self.fileURL)
    }

    static func defaultFileURL() -> URL {
        PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("voiceprint.json")
    }

    /// Start capturing the next `needed` wake utterances as the owner's profile.
    func beginEnrollment() { isEnrolling = true; enrolling = [] }

    var isActive: Bool { isEnrolling || (enabled && isEnrolled) }

    /// Decide whether a wake (with this utterance's voiceprint) should proceed.
    /// Always true while disabled, not enrolled, or enrolling.
    func accept(_ features: [Float]) -> Bool {
        if isEnrolling {
            enrolling.append(features)
            if enrolling.count >= needed {
                profile = SpeakerVerifier.averaged(enrolling)
                isEnrolling = false
                save()
                onEnrollmentComplete?()
            }
            return true
        }
        guard enabled, isEnrolled, !features.isEmpty else { return true }
        return SpeakerVerifier.matches(features, profile: profile, threshold: threshold)
    }

    func reset() { profile = []; isEnrolling = false; enrolling = []; save() }

    // MARK: Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(profile) { try? data.write(to: fileURL, options: .atomic) }
    }
    private static func load(from url: URL) -> [Float] {
        guard let data = try? Data(contentsOf: url),
              let v = try? JSONDecoder().decode([Float].self, from: data) else { return [] }
        return v
    }
}
