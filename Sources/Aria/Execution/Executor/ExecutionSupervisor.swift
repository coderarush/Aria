import Foundation

/// Retry / backoff policy for a single action (spec §13 execution policy).
struct ExecutionPolicy: Sendable {
    /// Retries *after* the first attempt. `maxRetries == 2` ⇒ up to 3 attempts.
    var maxRetries: Int
    /// Seconds to wait between attempts (0 disables sleeping).
    var backoff: TimeInterval

    init(maxRetries: Int = 2, backoff: TimeInterval = 0) {
        self.maxRetries = maxRetries
        self.backoff = backoff
    }
}

/// Supervises one action's run through a tool: prepare/execute/verify/cleanup,
/// with retry + backoff (spec §13). Timeout/deadlock handling is layered in by
/// the engine; the supervisor owns the retry loop and the always-cleanup rule.
struct ExecutionSupervisor: Sendable {

    enum SupervisorError: Error { case verificationFailed, notAttempted }

    let policy: ExecutionPolicy

    func run(_ action: Domain.Action, tool: any ExecutableTool) async -> Result<Domain.Artifact?, Error> {
        var lastError: Error = SupervisorError.notAttempted
        let attempts = max(1, policy.maxRetries + 1)

        for attempt in 0..<attempts {
            do {
                try await tool.prepare(action)
                let artifact = try await tool.execute(action)
                let verified = try await tool.verify(action, artifact)
                await tool.cleanup(action)
                if verified { return .success(artifact) }
                lastError = SupervisorError.verificationFailed
            } catch {
                lastError = error
                await tool.cleanup(action)
            }
            if policy.backoff > 0 && attempt < attempts - 1 {
                try? await Task.sleep(nanoseconds: UInt64(policy.backoff * 1_000_000_000))
            }
        }
        return .failure(lastError)
    }
}
