import XCTest
@testable import Aria

/// Live, network-hitting end-to-end probe of the autonomy pipeline. Skipped unless
/// ARIA_LIVE=1 so it never runs in CI / the normal suite. Run with:
///
///   ARIA_LIVE=1 ARIA_API_KEY="$(security find-generic-password -s Aria -a gemini-api-key -w)" \
///     swift test --filter LiveProbeTests
///
/// Prints the real plan, each step's result, and timing — the evidence that a goal
/// like "research X and save a note" actually completes.
final class LiveProbeTests: XCTestCase {
    func testResearchAndSaveEndToEnd() async throws {
        guard ProcessInfo.processInfo.environment["ARIA_LIVE"] == "1" else {
            throw XCTSkip("LiveProbe disabled (set ARIA_LIVE=1 to run)")
        }
        let key = ProcessInfo.processInfo.environment["ARIA_API_KEY"] ?? ""
        guard !key.isEmpty else { throw XCTSkip("no ARIA_API_KEY") }

        let gemini = GeminiClient(apiKeyProvider: { key })
        let orchestrator = AgentOrchestrator(gemini: gemini)

        let goal = ProcessInfo.processInfo.environment["ARIA_GOAL"]
            ?? "research the best usb mics and save a summary to a note"
        print("\n===== LIVE PROBE: \(goal) =====")

        let start = Date()
        let box = EventBox()
        await orchestrator.runTask(goal: goal) { ev in
            Task { await box.record(ev, since: start) }
        }
        // Give the trailing emit Tasks a moment to flush their prints.
        try? await Task.sleep(nanoseconds: 500_000_000)
        await box.dump()
        print("===== END (\(String(format: "%.1f", Date().timeIntervalSince(start)))s) =====\n")
    }
}

private actor EventBox {
    private var lines: [String] = []
    func record(_ ev: TaskEvent, since start: Date) {
        let t = String(format: "%6.1fs", Date().timeIntervalSince(start))
        switch ev {
        case .planReady(let plan):
            lines.append("[\(t)] PLAN (\(plan.total) steps):")
            for (i, s) in plan.steps.enumerated() {
                lines.append("         \(i + 1). \(s.summary)  [\(s.executor)]")
            }
        case .stepStarted(let i):
            lines.append("[\(t)] ▶ step \(i + 1) started")
        case .stepFinished(let i, let ok, let result):
            lines.append("[\(t)] \(ok ? "✓" : "✗") step \(i + 1): \(result.prefix(240).replacingOccurrences(of: "\n", with: " ⏎ "))")
        case .narrate(let line):
            lines.append("[\(t)] 🗣  \(line)")
        case .finished(let ok, let summary):
            lines.append("[\(t)] FINISHED ok=\(ok): \(summary)")
        }
    }
    func dump() { for l in lines { print(l) } }
}
