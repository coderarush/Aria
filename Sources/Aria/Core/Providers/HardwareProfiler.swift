import Foundation

/// V11 P1 — detect what this Mac can run locally and recommend the right
/// model tier. Pure decision logic + thin live readings; zero setup burden
/// on the user ("local first → cloud second" starts with the right default).
enum HardwareProfiler {

    struct Profile: Sendable, Equatable {
        let chip: String
        let ramGB: Int
        let freeDiskGB: Int
        let recommendedModel: String
    }

    /// Constitution tiers: 8GB → Qwen 3 4B, 16GB → 8B, 24GB+ → 14B.
    /// Disk guards: roughly 3/6/10 GB on disk per tier — never recommend a
    /// model the machine can't even store.
    static func recommendedModel(ramGB: Int, freeDiskGB: Int = .max) -> String {
        let byRAM: String
        switch ramGB {
        case ..<16: byRAM = "qwen3:4b"
        case ..<24: byRAM = "qwen3:8b"
        default:    byRAM = "qwen3:14b"
        }
        // Downgrade until the model fits the free disk (with headroom).
        if byRAM == "qwen3:14b" && freeDiskGB < 12 {
            return freeDiskGB < 8 ? (freeDiskGB < 5 ? "qwen3:4b" : "qwen3:8b") : "qwen3:8b"
        }
        if byRAM == "qwen3:8b" && freeDiskGB < 8 { return "qwen3:4b" }
        return byRAM
    }

    /// Live reading of this machine.
    static func profile() -> Profile {
        let ramGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        let chip = chipName()
        let disk = freeDiskGB()
        return Profile(chip: chip, ramGB: ramGB, freeDiskGB: disk,
                       recommendedModel: recommendedModel(ramGB: ramGB, freeDiskGB: disk))
    }

    /// "Apple M3 Pro" via sysctl; falls back to the architecture name.
    static func chipName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var chars = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &chars, &size, nil, 0)
        let name = String(cString: chars).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Apple Silicon" : name
    }

    static func freeDiskGB() -> Int {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else { return .max }
        return Int(capacity / (1024 * 1024 * 1024))
    }
}
