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

    /// Append a line to /tmp/friday.log for easy after-the-fact debugging.
    /// (os.Logger output is hard to retrieve; this file is trivial to read.)
    static func trace(_ message: String) {
        let line = "[\(Self.stamp())] \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/friday.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
