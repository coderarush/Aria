import Foundation

/// Search the web via DuckDuckGo's HTML endpoint (no key, free) and return the top
/// organic results — title, snippet, and real URL — so the model has actual content
/// to read and synthesize. (The old Instant-Answer API returned nothing for normal
/// queries like "best USB mics", which made research useless.)
struct WebSearchTool: AriaTool {
    static let name = "web_search"
    static let description = "Search the web and return the top results (title, snippet, link). Input: {query}."
    static let paramHints: [String: String] = ["query": "The search query"]

    var session: URLSession = .shared
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    func run(input: [String: String]) async throws -> ToolResult {
        guard let query = input["query"], !query.isEmpty else { throw ToolError.missingInput("query") }
        guard let url = Self.searchURL(query: query) else { return .fail("Bad query.") }

        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await session.data(for: req)
            let html = String(decoding: data, as: UTF8.self)
            let results = Self.parseResults(html)
            guard !results.isEmpty else {
                return .ok("No web results found for “\(query)”.")
            }
            let formatted = results.prefix(6).enumerated().map { i, r in
                "\(i + 1). \(r.title)\n   \(r.snippet)\n   \(r.url)"
            }.joined(separator: "\n\n")
            return .ok("Top results for “\(query)”:\n\n\(formatted)")
        } catch {
            return .fail("Search failed: \(error.localizedDescription)")
        }
    }

    /// Build a DuckDuckGo HTML search URL with proper query encoding.
    static func searchURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "html.duckduckgo.com"
        components.path = "/html/"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }

    /// Pull (title, url, snippet) triples out of DuckDuckGo's HTML results page.
    static func parseResults(_ html: String) -> [(title: String, url: String, snippet: String)] {
        let titleAnchors = regexMatches(#"<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, in: html)
        let snippetAnchors = regexMatches(#"<a[^>]*class="result__snippet"[^>]*>(.*?)</a>"#, in: html)
        var out: [(String, String, String)] = []
        for (i, m) in titleAnchors.enumerated() where m.count >= 3 {
            let url = realURL(from: m[1])
            let title = WebFetchTool.stripHTML(m[2])
            let snippet = i < snippetAnchors.count && snippetAnchors[i].count >= 2
                ? WebFetchTool.stripHTML(snippetAnchors[i][1]) : ""
            if !title.isEmpty, !url.isEmpty { out.append((title, url, snippet)) }
        }
        return out
    }

    /// DuckDuckGo wraps result links in a redirect (//duckduckgo.com/l/?uddg=…);
    /// pull the real destination out of the `uddg` param.
    static func realURL(from href: String) -> String {
        var h = href
        if h.hasPrefix("//") { h = "https:" + h }
        if let comps = URLComponents(string: h),
           let uddg = comps.queryItems?.first(where: { $0.name == "uddg" })?.value {
            return uddg
        }
        return h
    }

    static func regexMatches(_ pattern: String, in s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let range = NSRange(s.startIndex..., in: s)
        return re.matches(in: s, range: range).map { m in
            (0..<m.numberOfRanges).map { i -> String in
                guard let r = Range(m.range(at: i), in: s) else { return "" }
                return String(s[r])
            }
        }
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
