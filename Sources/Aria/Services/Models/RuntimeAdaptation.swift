import Foundation
import IOKit.ps

/// Conservative, local-only memory telemetry for the runtime policy. macOS
/// exposes page counters through sysctl; using those directly avoids spawning a
/// shell process in the routing path. Inactive and purgeable pages can be
/// reclaimed before an application must compete with working memory.
enum RuntimeMemoryReader {
    static func reclaimableGB(pageSize: UInt64, free: UInt64,
                              inactive: UInt64, purgeable: UInt64) -> Int? {
        guard pageSize > 0 else { return nil }
        let first = free.addingReportingOverflow(inactive)
        guard !first.overflow else { return nil }
        let pages = first.partialValue.addingReportingOverflow(purgeable)
        guard !pages.overflow else { return nil }
        let bytes = pages.partialValue.multipliedReportingOverflow(by: pageSize)
        guard !bytes.overflow, bytes.partialValue <= UInt64(Int.max) else { return nil }
        return Int(bytes.partialValue / (1 << 30))
    }

    static func liveReclaimableGB() -> Int? {
        guard let pageSize = sysctlValue("hw.pagesize"),
              let free = sysctlValue("vm.page_free_count"),
              let inactive = sysctlValue("vm.page_inactive_count"),
              let purgeable = sysctlValue("vm.page_purgeable_count") else {
            return nil
        }
        return reclaimableGB(pageSize: pageSize, free: free,
                             inactive: inactive, purgeable: purgeable)
    }

    private static func sysctlValue(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        let status = name.withCString {
            sysctlbyname($0, &value, &size, nil, 0)
        }
        guard status == 0, size > 0 else { return nil }
        return value
    }
}

/// A power-aware description of the Mac's current operating conditions.
/// Dynamic readings are deliberately represented as optional when macOS cannot
/// provide them truthfully; the policy always prefers a conservative fallback.
enum RuntimePowerSource: String, Codable, Sendable {
    case ac
    case battery
    case unavailable
}

enum RuntimeThermalState: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

enum RuntimePosture: String, Codable, Sendable {
    case performance
    case balanced
    case batterySaver
    case cooldown
    case constrained
}

struct RuntimeCapability: Codable, Equatable, Sendable {
    let chip: String
    let ramGB: Int
    let freeDiskGB: Int
    let powerSource: RuntimePowerSource
    let batteryPercent: Int?
    let lowPowerMode: Bool
    let thermalState: RuntimeThermalState
    let availableMemoryGB: Int?
    let lastLocalLatency: TimeInterval?
    let localFailureRate: Double?
}

struct RuntimeRecommendation: Codable, Equatable, Sendable {
    let posture: RuntimePosture
    let permitsLocalPlanning: Bool
    let permitsLocalChat: Bool
    let maxConcurrentLocalRequests: Int
    let planningModelCap: String?
    let chatModelCap: String?
    let reason: String
}

/// Live system reads are captured behind simple closures so the policy and
/// advisor can be exercised deterministically without depending on a test Mac.
struct RuntimeSignalReader: Sendable {
    let readPowerSource: @Sendable () -> RuntimePowerSource
    let readBatteryPercent: @Sendable () -> Int?
    let readLowPowerMode: @Sendable () -> Bool
    let readThermalState: @Sendable () -> RuntimeThermalState
    let readAvailableMemoryGB: @Sendable () -> Int?

    static let live = RuntimeSignalReader(
        readPowerSource: { currentPowerSource() },
        readBatteryPercent: { currentBatteryPercent() },
        readLowPowerMode: { ProcessInfo.processInfo.isLowPowerModeEnabled },
        readThermalState: { currentThermalState() },
        readAvailableMemoryGB: { RuntimeMemoryReader.liveReclaimableGB() })

    private static func currentPowerSource() -> RuntimePowerSource {
        guard let description = powerSourceDescription(),
              let state = description[kIOPSPowerSourceStateKey as String] as? String else {
            return .unavailable
        }
        if state == (kIOPSACPowerValue as String) { return .ac }
        if state == (kIOPSBatteryPowerValue as String) { return .battery }
        return .unavailable
    }

    private static func currentBatteryPercent() -> Int? {
        guard let description = powerSourceDescription() else { return nil }
        if let percent = description[kIOPSCurrentCapacityKey as String] as? Int { return percent }
        if let percent = description[kIOPSCurrentCapacityKey as String] as? NSNumber { return percent.intValue }
        return nil
    }

    private static func currentThermalState() -> RuntimeThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .serious
        }
    }

    private static func powerSourceDescription() -> [String: Any]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] {
                return description
            }
        }
        return nil
    }
}

/// Holds the last capability observation so routing and the native UI agree on
/// what Aria is doing. It stays in memory: the conditions are current, not user
/// data that needs to be retained.
actor RuntimeAdvisor {
    static let shared = RuntimeAdvisor()

    private let hardware: @Sendable () -> HardwareProfiler.Profile
    private let signals: RuntimeSignalReader
    private let health: LocalModelHealth
    private let now: @Sendable () -> Date
    private var latestCapability: RuntimeCapability?
    private var latestRecommendation: RuntimeRecommendation?

    init(hardware: @escaping @Sendable () -> HardwareProfiler.Profile = { HardwareProfiler.profile() },
         signals: RuntimeSignalReader = .live,
         health: LocalModelHealth = .shared,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.hardware = hardware
        self.signals = signals
        self.health = health
        self.now = now
    }

    func refresh() async -> RuntimeRecommendation {
        let profile = hardware()
        let modelHealth = await health.snapshot(at: now())
        let capability = RuntimeCapability(
            chip: profile.chip,
            ramGB: profile.ramGB,
            freeDiskGB: profile.freeDiskGB,
            powerSource: signals.readPowerSource(),
            batteryPercent: signals.readBatteryPercent(),
            lowPowerMode: signals.readLowPowerMode(),
            thermalState: signals.readThermalState(),
            availableMemoryGB: signals.readAvailableMemoryGB(),
            lastLocalLatency: modelHealth.lastLatency,
            localFailureRate: modelHealth.recentFailureRate)
        let recommendation = RuntimePolicy.select(capability)
        latestCapability = capability
        latestRecommendation = recommendation
        return recommendation
    }

    func recommendation() async -> RuntimeRecommendation {
        if let latestRecommendation { return latestRecommendation }
        return await refresh()
    }

    func capability() async -> RuntimeCapability {
        if let latestCapability { return latestCapability }
        _ = await refresh()
        return latestCapability!
    }
}

/// Pure, conservative policy for selecting how much local work is appropriate.
/// It is intentionally a ceiling: user choice can remain smaller, but is never
/// silently increased by runtime adaptation.
enum RuntimePolicy {
    static func select(_ capability: RuntimeCapability) -> RuntimeRecommendation {
        if capability.thermalState == .critical
            || capability.freeDiskGB < 5
            || (capability.availableMemoryGB ?? 2) <= 1 {
            return RuntimeRecommendation(
                posture: .constrained,
                permitsLocalPlanning: false,
                permitsLocalChat: false,
                maxConcurrentLocalRequests: 0,
                planningModelCap: nil,
                chatModelCap: nil,
                reason: capability.thermalState == .critical
                    ? "Mac is too warm for local work"
                    : "Mac capacity is constrained")
        }

        if capability.thermalState == .serious {
            return cooldown(reason: "Mac is warm; keeping local work light")
        }

        if capability.lowPowerMode
            && capability.powerSource == .battery
            && (capability.batteryPercent ?? 100) <= 25 {
            return cooldown(reason: "Low Power Mode is on")
        }

        if (capability.localFailureRate ?? 0) > 0.5
            || (capability.lastLocalLatency ?? 0) > 15 {
            return cooldown(reason: "Local model needs a recovery break")
        }

        if capability.powerSource == .battery {
            return RuntimeRecommendation(
                posture: .batterySaver,
                permitsLocalPlanning: true,
                permitsLocalChat: true,
                maxConcurrentLocalRequests: 1,
                planningModelCap: "qwen3:4b",
                chatModelCap: "llama3.2:1b",
                reason: "Preserving battery while keeping Aria local")
        }

        if capability.powerSource == .ac
            && capability.ramGB >= 24
            && capability.freeDiskGB >= 16
            && (capability.availableMemoryGB ?? 0) >= 6 {
            return RuntimeRecommendation(
                posture: .performance,
                permitsLocalPlanning: true,
                permitsLocalChat: true,
                maxConcurrentLocalRequests: 2,
                planningModelCap: "qwen3:14b",
                chatModelCap: "llama3.2:3b",
                reason: "Using this Mac's available headroom")
        }

        return RuntimeRecommendation(
            posture: .balanced,
            permitsLocalPlanning: true,
            permitsLocalChat: true,
            maxConcurrentLocalRequests: 1,
            planningModelCap: capability.ramGB < 16 ? "qwen3:4b" : "qwen3:8b",
            chatModelCap: capability.ramGB < 16 ? "llama3.2:1b" : "llama3.2:3b",
            reason: "Balanced for this Mac")
    }

    static func effectiveModel(selected: String, cap: String?) -> String {
        guard let cap,
              modelFamily(selected) == modelFamily(cap),
              let selectedRank = modelRank(selected),
              let capRank = modelRank(cap),
              selectedRank > capRank else {
            return selected
        }
        return cap
    }

    private static func cooldown(reason: String) -> RuntimeRecommendation {
        RuntimeRecommendation(
            posture: .cooldown,
            permitsLocalPlanning: false,
            permitsLocalChat: true,
            maxConcurrentLocalRequests: 1,
            planningModelCap: "qwen3:4b",
            chatModelCap: "llama3.2:1b",
            reason: reason)
    }

    private static func modelRank(_ model: String) -> Int? {
        switch model.lowercased() {
        case "qwen3:4b": return 1
        case "qwen3:8b": return 2
        case "qwen3:14b": return 3
        case "llama3.2:1b": return 1
        case "llama3.2:3b": return 2
        default: return nil
        }
    }

    private static func modelFamily(_ model: String) -> String? {
        switch model.lowercased() {
        case "qwen3:4b", "qwen3:8b", "qwen3:14b": return "qwen3"
        case "llama3.2:1b", "llama3.2:3b": return "llama3.2"
        default: return nil
        }
    }
}
