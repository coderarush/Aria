import Foundation

/// Learns the user's writing voice from their own words — on-device, opt-in — and
/// produces a draft-scoped instruction the model uses so Aria's drafts sound like
/// them. Samples are the user's typed/spoken turns: a rough but real proxy for
/// their register (casualness, contractions, emoji, length). Gated by the same
/// `app.personalizationEnabled` opt-in as the entity graph; wipes on disable.
actor StyleLearner {
    static let shared = StyleLearner()
    static let enabledKey = "app.personalizationEnabled"

    private let url: URL?
    private let defaults: UserDefaults
    private var samples: [String] = []
    private var cached: StyleProfile = StyleProfile.analyze([])
    private let cap = 60

    init(storeURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        url = storeURL ?? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("style-samples.json")
        if let url, let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([String].self, from: data) {
            samples = loaded
            cached = StyleProfile.analyze(loaded)
        }
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    /// Record one of the user's own messages as a style sample. A no-op (and a
    /// privacy wipe) when personalization is off.
    func observe(_ text: String) {
        guard isEnabled else {
            if !samples.isEmpty { samples = []; cached = StyleProfile.analyze([]); save() }
            return
        }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 8 else { return }   // skip trivial fragments
        samples.append(t)
        if samples.count > cap { samples.removeFirst(samples.count - cap) }
        cached = StyleProfile.analyze(samples)
        save()
    }

    func profile() -> StyleProfile { cached }

    /// A draft-scoped style instruction to prepend to a turn, or nil when off /
    /// nothing learned yet (so non-personalized turns are byte-identical).
    func draftStyleInstruction() -> String? {
        guard isEnabled, !samples.isEmpty else { return nil }
        return "When drafting a message or email for the user, " + cached.styleGuide()
    }

    private func save() {
        guard let url else { return }
        if let data = try? JSONEncoder().encode(samples) { try? data.write(to: url, options: .atomic) }
    }
}
