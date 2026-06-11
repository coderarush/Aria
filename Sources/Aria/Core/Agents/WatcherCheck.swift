import Foundation
import AppKit
import CryptoKit

/// V11 P7 — the precheck behind watcher triggers. Snapshots a source (matching
/// inbox mail, a web page), hashes it, and compares against the agent's stored
/// watermark. First sight primes silently; identical content stays quiet; only
/// a real change fires the agent's goal — with the fresh content as context.
enum WatcherCheck {

    enum Outcome: Equatable, Sendable {
        /// Source unreachable (Mail not running, page down) — skip quietly,
        /// keep the old watermark so a flap can't fire a false change.
        case unavailable
        /// First observation: store the watermark, don't fire.
        case primed(watermark: String)
        case unchanged
        case fired(context: String, watermark: String)
    }

    static func evaluate(current: String?, watermark: String?) -> Outcome {
        guard let current else { return .unavailable }
        let h = hash(current)
        guard let watermark else { return .primed(watermark: h) }
        return h == watermark ? .unchanged : .fired(context: current, watermark: h)
    }

    static func hash(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: snapshots

    /// Matching inbox mail as "sender | subject | date" rows — nil when Mail
    /// is unreachable. Only runs when Mail is already open: a background
    /// watcher must never launch apps or trigger permission prompts.
    static func mailSnapshot(query: String) async -> String? {
        let mailRunning = await MainActor.run {
            NSWorkspace.shared.runningApplications
                .contains { $0.bundleIdentifier == "com.apple.mail" }
        }
        guard mailRunning else { return nil }
        guard let result = try? await EmailSearchTool().run(input: ["query": query]),
              result.success else { return nil }
        // "No inbox emails matched" is a valid (empty) observation.
        return result.output
    }

    /// Page content at `url` — nil on any transport failure. Trimmed to keep
    /// hashes cheap and goal context bounded.
    static func urlSnapshot(_ urlString: String, cap: Int = 20_000) async -> String? {
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return String(text.prefix(cap))
    }
}
