import Foundation

/// Lightweight update check: asks the GitHub releases API for the latest version and,
/// if it's newer than the running build, surfaces a prompt with a link. No Sparkle
/// dependency, no signing keys — just a nudge to download the new release.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var newVersion: String?
    @Published private(set) var releaseURL: URL?
    @Published private(set) var checking = false

    private let repo = "coderarush/Aria"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func check() async {
        checking = true; defer { checking = false }
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String else { return }
        if Self.isNewer(tag, than: currentVersion) {
            newVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            releaseURL = URL(string: obj["html_url"] as? String ?? "https://github.com/\(repo)/releases/latest")
        } else {
            newVersion = nil; releaseURL = nil
        }
    }

    /// Semantic version compare; tolerates a leading "v" and missing components.
    nonisolated static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.lowercased().replacingOccurrences(of: "v", with: "")
                .split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(tag), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
