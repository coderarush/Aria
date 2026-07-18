import AppKit
import Foundation

/// What must be true AFTER a step for it to count as actually done — so the engine
/// verifies effects, not just "the call didn't throw". Kept simple + checkable
/// against the step's textual result; richer (AX-state) checks can plug in later.
enum PostCondition: Sendable, Equatable, Codable {
    case none                    // no explicit check (default — back-compat)
    case succeeded               // the step's tool reported ok
    case resultContains(String)  // the result text contains a marker (and ok)
    case appRunning(String)      // a named Mac app is now running
    case appNotRunning(String)   // a named Mac app has quit
    case fileExists(String)      // a local file exists at the expected path

    /// A compact, user-readable statement of the state the step must establish.
    var expectation: String {
        switch self {
        case .none: return ""
        case .succeeded: return "the action completed"
        case .resultContains(let marker): return "the result contains \u{201c}\(marker)\u{201d}"
        case .appRunning(let name): return "\(name) is running"
        case .appNotRunning(let name): return "\(name) is no longer running"
        case .fileExists: return "the file exists"
        }
    }

    func isSatisfied(byResult result: String, ok: Bool) -> Bool {
        switch self {
        case .none: return true
        case .succeeded: return ok
        case .resultContains(let s): return ok && result.lowercased().contains(s.lowercased())
        case .appRunning, .appNotRunning, .fileExists: return ok
        }
    }
}

/// Result of checking the intended effect of a completed step. The proof is kept
/// short so it fits in the activity panel and speech response without leaking
/// raw app state.
struct PostConditionCheck: Sendable, Equatable {
    let passed: Bool
    let proof: String
}

/// Checks the state a task step promised to create. It is dependency-injected so
/// tests remain deterministic and the execution engine can poll a real app only
/// when a plan explicitly asks for an app-state contract.
struct PostConditionVerifier: Sendable {
    private let isAppRunning: @Sendable (String) async -> Bool
    private let fileExists: @Sendable (String) async -> Bool
    private let attempts: Int
    private let retryDelayNanoseconds: UInt64

    init(isAppRunning: @escaping @Sendable (String) async -> Bool,
         fileExists: @escaping @Sendable (String) async -> Bool = { path in
             FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath)
         },
         attempts: Int = 8,
         retryDelayNanoseconds: UInt64 = 200_000_000) {
        self.isAppRunning = isAppRunning
        self.fileExists = fileExists
        self.attempts = max(1, attempts)
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    /// The production checker uses NSWorkspace on the main actor. Matching both
    /// localized and bundle names handles user-facing names such as \"Notes\" and
    /// \"Visual Studio Code\" without trusting a tool's completion text.
    static let live = PostConditionVerifier(isAppRunning: { expected in
        await MainActor.run {
            NSWorkspace.shared.runningApplications.contains { app in
                let candidates = [
                    app.localizedName ?? "",
                    app.bundleURL?.deletingPathExtension().lastPathComponent ?? "",
                    app.bundleIdentifier ?? ""
                ]
                return candidates.contains { appNameMatches(running: $0, expected: expected) }
            }
        }
    })

    func verify(_ condition: PostCondition, result: ToolResult) async -> PostConditionCheck {
        guard result.success else {
            return PostConditionCheck(passed: false, proof: "Tool did not complete successfully.")
        }

        switch condition {
        case .none:
            return PostConditionCheck(passed: true, proof: "")

        case .succeeded:
            return PostConditionCheck(passed: true, proof: "Confirmed the action completed.")

        case .resultContains(let marker):
            let passed = result.output.localizedCaseInsensitiveContains(marker)
            return PostConditionCheck(
                passed: passed,
                proof: passed
                    ? "Confirmed the result contains \u{201c}\(marker)\u{201d}."
                    : "Couldn't confirm the result contains \u{201c}\(marker)\u{201d}.")

        case .appRunning(let name):
            let passed = await waitForApp(named: name, toBeRunning: true)
            let displayName = Self.displayName(name)
            return PostConditionCheck(
                passed: passed,
                proof: passed ? "Confirmed \(displayName) is running." : "Couldn't confirm \(displayName) launched.")

        case .appNotRunning(let name):
            let passed = await waitForApp(named: name, toBeRunning: false)
            let displayName = Self.displayName(name)
            return PostConditionCheck(
                passed: passed,
                proof: passed ? "Confirmed \(displayName) closed." : "Couldn't confirm \(displayName) closed.")

        case .fileExists(let path):
            let passed = await waitForFile(at: path)
            return PostConditionCheck(
                passed: passed,
                proof: passed ? "Confirmed the file exists." : "Couldn't confirm the file exists.")
        }
    }

    /// Public for pure tests and shared app-name handling. `.app` suffixes and
    /// case differences must not turn an otherwise deterministic verification
    /// into a false failure.
    static func appNameMatches(running: String, expected: String) -> Bool {
        normalizedAppName(running) == normalizedAppName(expected)
    }

    private func waitForApp(named name: String, toBeRunning wanted: Bool) async -> Bool {
        for attempt in 0..<attempts {
            if await isAppRunning(name) == wanted { return true }
            guard attempt + 1 < attempts, retryDelayNanoseconds > 0 else { continue }
            try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
        }
        return false
    }

    private func waitForFile(at path: String) async -> Bool {
        for attempt in 0..<attempts {
            if await fileExists(path) { return true }
            guard attempt + 1 < attempts, retryDelayNanoseconds > 0 else { continue }
            try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
        }
        return false
    }

    private static func normalizedAppName(_ name: String) -> String {
        var normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasSuffix(".app") { normalized.removeLast(4) }
        return normalized
    }

    private static func displayName(_ name: String) -> String {
        var display = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if display.lowercased().hasSuffix(".app") { display.removeLast(4) }
        return display == display.lowercased() ? display.capitalized : display
    }
}
