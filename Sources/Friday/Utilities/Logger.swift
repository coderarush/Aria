import Foundation
import os

/// Unified logging for Friday. Thin wrapper over `os.Logger` with per-subsystem
/// categories so console filtering is easy (`subsystem:com.friday.agent`).
enum Log {
    private static let subsystem = "com.friday.agent"

    static let app    = Logger(subsystem: subsystem, category: "app")
    static let wake   = Logger(subsystem: subsystem, category: "wake")
    static let screen = Logger(subsystem: subsystem, category: "screen")
    static let gemini = Logger(subsystem: subsystem, category: "gemini")
    static let agent  = Logger(subsystem: subsystem, category: "agent")
    static let ui     = Logger(subsystem: subsystem, category: "ui")
    static let memory = Logger(subsystem: subsystem, category: "memory")
}
