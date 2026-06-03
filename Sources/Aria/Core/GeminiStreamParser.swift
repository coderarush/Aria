import Foundation

/// One streamed item from Gemini.
enum StreamEvent: Equatable {
    case text(String)
    case functionCall(name: String, args: [String: String])
}

/// Incremental SSE parser for Gemini `streamGenerateContent?alt=sse`. Feed it raw
/// bytes-as-string as they arrive; it buffers partial lines and emits StreamEvents
/// when complete `data:` JSON objects are seen.
struct GeminiStreamParser {
    private var buffer = ""

    mutating func consume(_ chunk: String) -> [StreamEvent] {
        buffer += chunk
        var events: [StreamEvent] = []
        while let nl = buffer.range(of: "\n") {
            let line = String(buffer[..<nl.lowerBound])
            buffer = String(buffer[nl.upperBound...])
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" { continue }
            guard let data = payload.data(using: .utf8) else { continue }
            events.append(contentsOf: Self.events(fromJSON: data))
        }
        return events
    }

    static func events(fromJSON data: Data) -> [StreamEvent] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cands = root["candidates"] as? [[String: Any]],
            let content = cands.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else { return [] }
        var out: [StreamEvent] = []
        for part in parts {
            if let t = part["text"] as? String, !t.isEmpty {
                out.append(.text(t))
            } else if let fc = part["functionCall"] as? [String: Any],
                      let name = fc["name"] as? String {
                let rawArgs = fc["args"] as? [String: Any] ?? [:]
                var args: [String: String] = [:]
                for (k, v) in rawArgs { args[k] = String(describing: v) }
                out.append(.functionCall(name: name, args: args))
            }
        }
        return out
    }
}
