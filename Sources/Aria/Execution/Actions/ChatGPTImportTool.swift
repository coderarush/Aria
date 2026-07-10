import Foundation

/// Import Aria-related material from a local ChatGPT data export. Codex cannot
/// read the user's normal ChatGPT account directly, but the user can export their
/// data and point Aria at `conversations.json`.
struct ChatGPTImportTool: AriaTool {
    static let name = "chatgpt_import"
    static let description = "Import Aria-related notes from a local ChatGPT export conversations.json. Input: {path, query?, limit?}. Query defaults to 'Aria'. Stores matching snippets in long-term memory."
    static let paramHints: [String: String] = [
        "path": "Path to ChatGPT export conversations.json",
        "query": "Topic to extract; defaults to Aria",
        "limit": "Maximum snippets to import; default 20"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let rawPath = input["path"], !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolError.missingInput("path")
        }
        let path = (rawPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .fail("Couldn't read ChatGPT export at \(path): \(error.localizedDescription)")
        }

        let query = input["query"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Aria"
        let limit = Int(input["limit"] ?? "") ?? 20
        let hits: [ChatGPTExportImporter.Hit]
        do {
            hits = try ChatGPTExportImporter.extract(from: data, query: query, limit: limit)
        } catch {
            return .fail("Couldn't parse that ChatGPT export: \(error.localizedDescription)")
        }

        guard !hits.isEmpty else {
            return .ok("No ChatGPT conversations matched “\(query)”.")
        }

        var added = 0
        for hit in hits {
            let remembered = await LongTermMemory.shared.remember(
                "From ChatGPT export — \(hit.title): \(hit.snippet)",
                kind: "import")
            if remembered { added += 1 }
        }

        let preview = hits.prefix(6)
            .map { "• \($0.title): \($0.snippet)" }
            .joined(separator: "\n")
        return .ok("Imported \(added) new ChatGPT note\(added == 1 ? "" : "s") about “\(query)” into Aria memory.\n\(preview)")
    }
}

enum ChatGPTExportImporter {
    struct Hit: Equatable {
        let title: String
        let snippet: String
    }

    static func extract(from data: Data, query: String = "Aria", limit: Int = 20) throws -> [Hit] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ToolError.executionFailed("expected a ChatGPT conversations.json array")
        }
        let terms = tokens(query.isEmpty ? "Aria" : query)
        let capped = max(1, min(limit, 100))

        var hits: [Hit] = []
        var seen = Set<String>()
        for conversation in root {
            let title = (conversation["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled ChatGPT chat"
            let messages = messages(in: conversation)
            let haystack = ([title] + messages).joined(separator: "\n").lowercased()
            guard terms.contains(where: haystack.contains) else { continue }

            let relevant = messages.first { message in
                let lower = message.lowercased()
                return terms.contains(where: lower.contains)
            } ?? messages.first ?? title
            let snippet = compact(relevant, max: 280)
            let key = "\(title.lowercased())|\(snippet.lowercased())"
            guard seen.insert(key).inserted else { continue }
            hits.append(Hit(title: title, snippet: snippet))
            if hits.count >= capped { break }
        }
        return hits
    }

    private static func messages(in conversation: [String: Any]) -> [String] {
        guard let mapping = conversation["mapping"] as? [String: Any] else { return [] }
        let nodes = mapping.values.compactMap { $0 as? [String: Any] }
        return nodes
            .compactMap { node -> (Double, String)? in
                guard let message = node["message"] as? [String: Any],
                      let content = message["content"] as? [String: Any] else { return nil }
                let created = (message["create_time"] as? Double) ?? 0
                let text = partsText(content["parts"])
                guard !text.isEmpty else { return nil }
                return (created, text)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    private static func partsText(_ raw: Any?) -> String {
        guard let parts = raw as? [Any] else { return "" }
        return parts.compactMap { part -> String? in
            if let s = part as? String { return s }
            if let dict = part as? [String: Any] {
                return dict["text"] as? String
                    ?? dict["content"] as? String
                    ?? dict["name"] as? String
            }
            return nil
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }

    private static func compact(_ text: String, max: Int) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > max else { return flat }
        return String(flat.prefix(max)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
