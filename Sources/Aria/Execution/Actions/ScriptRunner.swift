import Foundation

/// Executes a short script in one of the supported languages, in an isolated
/// temp working directory, with a hard timeout. Captures stdout/stderr.
///
/// Isolation note: v1 isolates via a per-run temp cwd + timeout + scoped env.
/// It does NOT yet confine filesystem/network at the OS level — true sandboxing
/// (sandbox-exec profile or an XPC sandbox helper) is a tracked hardening task.
/// Destructive intent is gated upstream by user confirmation.
final class ScriptRunner {

    struct Output {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var success: Bool { exitCode == 0 }
    }

    /// Resolve an interpreter path for a language, preferring known locations.
    static func interpreter(for language: ToolLanguage) -> (path: String, args: [String])? {
        switch language {
        case .python:
            for p in ["/usr/local/bin/python3.11", "/opt/homebrew/bin/python3", "/usr/bin/python3"] {
                if FileManager.default.isExecutableFile(atPath: p) { return (p, []) }
            }
            return which("python3").map { ($0, []) }
        case .bash:
            return ("/bin/bash", [])
        case .javascript:
            for p in ["/opt/homebrew/bin/node", "/usr/local/bin/node"] {
                if FileManager.default.isExecutableFile(atPath: p) { return (p, []) }
            }
            return which("node").map { ($0, []) }
        case .applescript:
            return ("/usr/bin/osascript", [])
        }
    }

    private static func which(_ tool: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["which", tool]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func fileExtension(for language: ToolLanguage) -> String {
        switch language {
        case .python: return "py"
        case .bash: return "sh"
        case .javascript: return "js"
        case .applescript: return "scpt"
        }
    }

    /// Run `code` in `language` with a timeout. Returns captured output, or
    /// throws `ToolError` on missing interpreter / timeout.
    func run(code: String,
             language: ToolLanguage,
             timeout: TimeInterval = 60) async throws -> Output {

        guard let interp = Self.interpreter(for: language) else {
            throw ToolError.interpreterNotFound(language.rawValue)
        }

        // Isolated working directory.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let scriptURL = workDir.appendingPathComponent("script.\(Self.fileExtension(for: language))")
        try code.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: interp.path)
        process.arguments = interp.args + [scriptURL.path]
        process.currentDirectoryURL = workDir
        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin",
            "ARIA_SANDBOX": "1"
        ]

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Output, Error>) in
                let didResume = ResumeGuard()

                // Timeout watchdog.
                let timeoutWork = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                    if didResume.tryResume() {
                        cont.resume(throwing: ToolError.timedOut)
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

                process.terminationHandler = { proc in
                    timeoutWork.cancel()
                    guard didResume.tryResume() else { return }
                    let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    cont.resume(returning: Output(exitCode: proc.terminationStatus, stdout: out, stderr: err))
                }

                do { try process.run() }
                catch {
                    timeoutWork.cancel()
                    if didResume.tryResume() {
                        cont.resume(throwing: ToolError.executionFailed(error.localizedDescription))
                    }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

/// Tiny thread-safe latch so the continuation is resumed exactly once.
private final class ResumeGuard {
    private let lock = NSLock()
    private var resumed = false
    func tryResume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}
