import XCTest
@testable import Aria

final class RuntimeAdaptationTests: XCTestCase {
    private func makeCapability(power: RuntimePowerSource = .ac, battery: Int? = 92,
                                lowPower: Bool = false, thermal: RuntimeThermalState = .nominal,
                                ram: Int = 16, disk: Int = 40, memory: Int? = 8,
                                latency: TimeInterval? = 1.2, failures: Double? = 0) -> RuntimeCapability {
        RuntimeCapability(chip: "Apple M4", ramGB: ram, freeDiskGB: disk,
                          powerSource: power, batteryPercent: battery,
                          lowPowerMode: lowPower, thermalState: thermal,
                          availableMemoryGB: memory, lastLocalLatency: latency,
                          localFailureRate: failures)
    }

    func testHealthyACOn16GBUsesBalancedLocalWork() {
        let result = RuntimePolicy.select(makeCapability())
        XCTAssertEqual(result.posture, .balanced)
        XCTAssertTrue(result.permitsLocalPlanning)
        XCTAssertTrue(result.permitsLocalChat)
        XCTAssertEqual(result.maxConcurrentLocalRequests, 1)
        XCTAssertEqual(result.planningModelCap, "qwen3:8b")
    }

    func testHealthyACOn24GBUsesPerformancePosture() {
        let result = RuntimePolicy.select(makeCapability(ram: 24, disk: 48, memory: 14))
        XCTAssertEqual(result.posture, .performance)
        XCTAssertEqual(result.maxConcurrentLocalRequests, 2)
        XCTAssertEqual(result.planningModelCap, "qwen3:14b")
    }

    func testReclaimableMemoryCombinesConservativePageClasses() {
        XCTAssertEqual(RuntimeMemoryReader.reclaimableGB(
            pageSize: 16_384, free: 131_072, inactive: 262_144, purgeable: 65_536), 7)
    }

    func testReclaimableMemoryRejectsOverflow() {
        XCTAssertNil(RuntimeMemoryReader.reclaimableGB(
            pageSize: UInt64.max, free: 2, inactive: 0, purgeable: 0))
    }

    func testBatteryUsesSmallModelsAndOneRequest() {
        let result = RuntimePolicy.select(makeCapability(power: .battery, battery: 73))
        XCTAssertEqual(result.posture, .batterySaver)
        XCTAssertEqual(result.planningModelCap, "qwen3:4b")
        XCTAssertEqual(result.chatModelCap, "llama3.2:1b")
        XCTAssertEqual(result.maxConcurrentLocalRequests, 1)
    }

    func testLowPowerAndLowBatteryCooldownsPlanning() {
        let result = RuntimePolicy.select(makeCapability(power: .battery, battery: 18, lowPower: true))
        XCTAssertEqual(result.posture, .cooldown)
        XCTAssertFalse(result.permitsLocalPlanning)
        XCTAssertTrue(result.permitsLocalChat)
        XCTAssertTrue(result.reason.localizedCaseInsensitiveContains("Low Power"))
    }

    func testCriticalThermalsDisableAllLocalRouting() {
        let result = RuntimePolicy.select(makeCapability(thermal: .critical))
        XCTAssertEqual(result.posture, .constrained)
        XCTAssertFalse(result.permitsLocalPlanning)
        XCTAssertFalse(result.permitsLocalChat)
        XCTAssertEqual(result.maxConcurrentLocalRequests, 0)
    }

    func testLowDiskLowMemoryAndPoorHealthConstrainOrCooldown() {
        XCTAssertEqual(RuntimePolicy.select(makeCapability(disk: 4)).posture, .constrained)
        XCTAssertEqual(RuntimePolicy.select(makeCapability(memory: 1)).posture, .constrained)
        XCTAssertEqual(RuntimePolicy.select(makeCapability(latency: 16)).posture, .cooldown)
        XCTAssertEqual(RuntimePolicy.select(makeCapability(failures: 0.51)).posture, .cooldown)
    }

    func testEffectiveModelCanOnlyStepDownKnownModels() {
        XCTAssertEqual(RuntimePolicy.effectiveModel(selected: "qwen3:14b", cap: "qwen3:4b"), "qwen3:4b")
        XCTAssertEqual(RuntimePolicy.effectiveModel(selected: "qwen3:4b", cap: "qwen3:14b"), "qwen3:4b")
        XCTAssertEqual(RuntimePolicy.effectiveModel(selected: "llama3.2:3b", cap: "llama3.2:1b"), "llama3.2:1b")
        XCTAssertEqual(RuntimePolicy.effectiveModel(selected: "qwen3:14b", cap: "llama3.2:1b"), "qwen3:14b")
        XCTAssertEqual(RuntimePolicy.effectiveModel(selected: "custom-model", cap: "qwen3:4b"), "custom-model")
    }

    func testAdvisorUsesInjectedSignalsAndHealth() async {
        let signals = RuntimeSignalReader(
            readPowerSource: { .battery },
            readBatteryPercent: { 19 },
            readLowPowerMode: { true },
            readThermalState: { .nominal },
            readAvailableMemoryGB: { 6 })
        let health = LocalModelHealth()
        await health.record(ok: false, latency: 0, error: "timeout")
        await health.record(ok: false, latency: 0, error: "timeout")
        let advisor = RuntimeAdvisor(
            hardware: { .init(chip: "Test Mac", ramGB: 16, freeDiskGB: 40, recommendedModel: "qwen3:8b") },
            signals: signals,
            health: health)

        let result = await advisor.refresh()
        let capability = await advisor.capability()

        XCTAssertEqual(result.posture, .cooldown)
        XCTAssertEqual(capability.batteryPercent, 19)
    }

    func testAdvisorIgnoresExpiredHealthFailures() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let signals = RuntimeSignalReader(
            readPowerSource: { .ac },
            readBatteryPercent: { nil },
            readLowPowerMode: { false },
            readThermalState: { .nominal },
            readAvailableMemoryGB: { 8 })
        let health = LocalModelHealth(window: 60, maximumObservations: 8)
        await health.record(ok: false, latency: 0, error: "timeout", at: start)
        await health.record(ok: true, latency: 0.2, at: start.addingTimeInterval(61))
        let advisor = RuntimeAdvisor(
            hardware: { .init(chip: "Test Mac", ramGB: 16, freeDiskGB: 40, recommendedModel: "qwen3:8b") },
            signals: signals,
            health: health,
            now: { start.addingTimeInterval(61) })

        let result = await advisor.refresh()

        XCTAssertEqual(result.posture, .balanced)
    }
}
