import Foundation

/// Search the web via DuckDuckGo's free Instant Answer API (no key).
struct WebSearchTool: AriaTool {
    static let name = "web_search"
    static let description = "Search the web (DuckDuckGo instant answers). Input: {query}."
    static let paramHints: [String: String] = ["query": "The search query"]

    var session: URLSession = .shared

    func run(input: [String: String]) async throws -> ToolResult {
        guard let query = input["query"], !query.isEmpty else { throw ToolError.missingInput("query") }
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1")
        else { return .fail("Bad query.") }

        do {
            let (data, _) = try await session.data(from: url)
            return .ok(Self.summarize(data, query: query))
        } catch {
            return .fail("Search failed: \(error.localizedDescription)")
        }
    }

    static func summarize(_ data: Data, query: String) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "No results for \(query)."
        }
        if let abstract = root["AbstractText"] as? String, !abstract.isEmpty {
            let src = root["AbstractURL"] as? String ?? ""
            return src.isEmpty ? abstract : "\(abstract)\n\nSource: \(src)"
        }
        if let related = root["RelatedTopics"] as? [[String: Any]] {
            let texts = related.compactMap { $0["Text"] as? String }.prefix(3)
            if !texts.isEmpty { return texts.joined(separator: "\n• ") }
        }
        if let answer = root["Answer"] as? String, !answer.isEmpty { return answer }
        return "No instant answer for \(query). Try a more specific query."
    }
}

/// Fetch a webpage and return readable text (HTML stripped).
struct WebFetchTool: AriaTool {
    static let name = "web_fetch"
    static let description = "Fetch a webpage and return readable text. Input: {url}."
    static let paramHints: [String: String] = ["url": "The URL to fetch"]

    var session: URLSession = .shared
    private let maxChars = 6000

    func run(input: [String: String]) async throws -> ToolResult {
        guard let raw = input["url"], !raw.isEmpty else { throw ToolError.missingInput("url") }
        let normalized = raw.hasPrefix("http") ? raw : "https://\(raw)"
        guard let url = URL(string: normalized) else { return .fail("Invalid URL.") }
        do {
            let (data, _) = try await session.data(from: url)
            let html = String(decoding: data, as: UTF8.self)
            let text = Self.stripHTML(html)
            return .ok(String(text.prefix(maxChars)))
        } catch {
            return .fail("Fetch failed: \(error.localizedDescription)")
        }
    }

    /// Crude but dependency-free HTML → text: drop script/style, strip tags,
    /// decode a few entities, collapse whitespace.
    static func stripHTML(_ html: String) -> String {
        var s = html
        for tag in ["script", "style", "head", "noscript"] {
            s = s.replacingOccurrences(
                of: "<\(tag)[^>]*>.*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
                        "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
