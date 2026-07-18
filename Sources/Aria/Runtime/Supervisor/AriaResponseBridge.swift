import Foundation

/// The typed production seam for the command path (spec §51/52).
///
/// Unlike the generic ``RuntimeBridge`` (which works at the string level for
/// parity machinery), this bridge preserves the full ``AriaResponse``:
/// - `.legacy` / `.shadow` / `.dual` — returns the orchestrator's response
///   byte-identical, so wiring it into the live path changes nothing. Shadow/
///   dual additionally run the runtime silently and emit a `shadowCompared`
///   event.
/// - `.preferred` / `.runtimeOnly` — serve the runtime, synthesizing a response
///   from its output, with legacy fallback on failure. Only reached after the
///   migration is deliberately advanced past on-device parity.
/// - `.cleanup` — runtime only.
actor AriaResponseBridge {

    private(set) var stage: MigrationStage
    private let legacy: any CommandHandling
    private let runtime: any RuntimeExecutor
    private let eventBus: EventBus

    init(stage: MigrationStage = .legacy,
         legacy: any CommandHandling,
         runtime: any RuntimeExecutor,
         eventBus: EventBus) {
        self.stage = stage
        self.legacy = legacy
        self.runtime = runtime
        self.eventBus = eventBus
    }

    func setStage(_ newStage: MigrationStage) { stage = newStage }

    func handle(command: String, privacyMode: Bool) async -> AriaResponse {
        switch stage {
        case .legacy:
            return await legacy.handle(command: command, privacyMode: privacyMode)

        case .shadow, .dual:
            let legacyResponse = await legacy.handle(command: command, privacyMode: privacyMode)
            let runtimeResult = await runtime.execute(BridgeRequest(objective: command))
            let equal = legacyResponse.message == runtimeResult.output
            await eventBus.emit(AriaEvent(
                kind: .shadowCompared,
                source: "AriaResponseBridge",
                payload: ["equal": String(equal), "stage": stage.rawValue]))
            return legacyResponse   // user always sees the exact legacy response

        case .preferred, .runtimeOnly:
            let runtimeResult = await runtime.execute(BridgeRequest(objective: command))
            if runtimeResult.success {
                return AriaResponse(type: .answer, message: runtimeResult.output,
                                    confidence: 1.0, succeeded: true)
            }
            return await legacy.handle(command: command, privacyMode: privacyMode)

        case .cleanup:
            let runtimeResult = await runtime.execute(BridgeRequest(objective: command))
            return AriaResponse(type: .answer, message: runtimeResult.output,
                                confidence: 1.0, succeeded: runtimeResult.success)
        }
    }
}
