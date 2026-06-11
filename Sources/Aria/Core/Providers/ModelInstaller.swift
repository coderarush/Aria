import Foundation

/// V11 P1 — gets the recommended local model onto this machine with zero
/// manual setup: detects Ollama, starts it when possible, pulls the model
/// with live progress, and reports a single setup status the UI can act on.
/// All network work targets localhost; pure decision/parsing logic is static
/// and unit-tested.
actor ModelInstaller {
    static let shared = ModelInstaller()

    enum SetupStatus: Equatable, Sendable {
        case ollamaMissing   // runtime not installed — needs the user (download link)
        case serverDown      // installed but not running — we can try to start it
        case modelMissing    // server up, wanted model not pulled yet
        case ready
    }

    struct PullProgress: Sendable, Equatable {
        let status: String
        let fraction: Double   // 0…1 where known
        let done: Bool
        let error: String?
    }

    // MARK: pure decisions (unit-tested)

    static func status(binaryPresent: Bool, serverAlive: Bool,
                       installedModels: [String], wanted: String) -> SetupStatus {
        if serverAlive {
            let have = installedModels.contains { $0 == wanted || $0.hasPrefix(wanted + ":") }
            return have ? .ready : .modelMissing
        }
        return binaryPresent ? .serverDown : .ollamaMissing
    }

    /// One NDJSON line from POST /api/pull → progress. nil for unparseable lines.
    static func progress(fromPullLine data: Data) -> PullProgress? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = obj["error"] as? String {
            return PullProgress(status: "error", fraction: 0, done: false, error: error)
        }
        let status = obj["status"] as? String ?? ""
        if status == "success" {
            return PullProgress(status: status, fraction: 1, done: true, error: nil)
        }
        let completed = (obj["completed"] as? Double) ?? Double(obj["completed"] as? Int ?? 0)
        let total = (obj["total"] as? Double) ?? Double(obj["total"] as? Int ?? 0)
        let fraction = total > 0 ? min(1, completed / total) : 0
        return PullProgress(status: status, fraction: fraction, done: false, error: nil)
    }

    // MARK: live checks

    /// Ollama present as a CLI or app? (binary in the usual places, or Ollama.app)
    nonisolated static func ollamaBinaryPresent() -> Bool {
        let fm = FileManager.default
        let candidates = [
            "/usr/local/bin/ollama", "/opt/homebrew/bin/ollama",
            "/Applications/Ollama.app", NSHomeDirectory() + "/Applications/Ollama.app"
        ]
        return candidates.contains { fm.fileExists(atPath: $0) }
    }

    nonisolated static func serverAlive() async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        guard let (_, response) = try? await URLSession.shared.data(for: req) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    nonisolated static func installedModels() async -> [String] {
        guard let url = URL(string: "http://localhost:11434/api/tags"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    /// Full current setup picture for `wanted`.
    nonisolated static func currentStatus(wanted: String) async -> SetupStatus {
        let alive = await serverAlive()
        let models = alive ? await installedModels() : []
        return status(binaryPresent: ollamaBinaryPresent(), serverAlive: alive,
                      installedModels: models, wanted: wanted)
    }

    /// Best-effort server start: launch Ollama.app when present (it owns the
    /// daemon), else `ollama serve` detached. Returns once the server answers
    /// or the timeout passes.
    nonisolated static func startServer(timeout: TimeInterval = 15) async -> Bool {
        if await serverAlive() { return true }
        let fm = FileManager.default
        if fm.fileExists(atPath: "/Applications/Ollama.app")
            || fm.fileExists(atPath: NSHomeDirectory() + "/Applications/Ollama.app") {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", "Ollama", "--background"]
            try? p.run()
        } else if let bin = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
            .first(where: { fm.fileExists(atPath: $0) }) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["serve"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
        } else {
            return false
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await serverAlive() { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    /// Pull `model` with live progress. Throws on transport failure; yields a
    /// final `done` progress on success.
    nonisolated static func pull(model: String,
                                 onProgress: @escaping @Sendable (PullProgress) -> Void) async throws {
        guard let url = URL(string: "http://localhost:11434/api/pull") else {
            throw ToolError.executionFailed("bad ollama url")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 3600   // big models on slow links take a while
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": model, "stream": true])
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ToolError.executionFailed("ollama pull http error")
        }
        for try await line in bytes.lines {
            guard let p = progress(fromPullLine: Data(line.utf8)) else { continue }
            onProgress(p)
            if let error = p.error { throw ToolError.executionFailed(error) }
        }
    }
}

/// V11 P1 — local model health: success/failure counts and last latency,
/// surfaced in Settings so "is local actually working?" is never a mystery.
actor LocalModelHealth {
    static let shared = LocalModelHealth()

    struct Snapshot: Sendable, Equatable {
        let successes: Int
        let failures: Int
        let lastLatency: Double?
        let lastError: String?
        let lastSuccessAt: Date?
    }

    private var successes = 0
    private var failures = 0
    private var lastLatency: Double?
    private var lastError: String?
    private var lastSuccessAt: Date?

    func record(ok: Bool, latency: Double, error: String? = nil, at date: Date = Date()) {
        if ok {
            successes += 1
            lastLatency = latency
            lastSuccessAt = date
        } else {
            failures += 1
            lastError = error
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(successes: successes, failures: failures, lastLatency: lastLatency,
                 lastError: lastError, lastSuccessAt: lastSuccessAt)
    }
}
