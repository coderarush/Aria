import Foundation

struct SearchResult: Sendable {
    var title: String
    var url: String
    var snippet: String
}

struct ReportSection: Codable, Sendable, Equatable {
    var heading: String
    var content: String
}

struct ResearchReport: Codable, Sendable, Identifiable {
    let id: UUID
    var topic: String
    var date: Date
    var sections: [ReportSection]
    var keyFindings: [String]
    var sources: [String]
}

/// The generated report and the durable file that was actually written for it.
/// A missing URL means research succeeded but local persistence did not.
struct ResearchOutcome: Sendable {
    let report: ResearchReport
    let savedURL: URL?
}

struct ResearchEngine: Sendable {
    // Injectable for tests
    var search: @Sendable (String) async -> [SearchResult]
    var fetchPage: @Sendable (String) async -> String
    private let reportsDirectory: URL

    init(
        reportsDirectory: URL = ResearchEngine.defaultReportsDirectory,
        search: @escaping @Sendable (String) async -> [SearchResult] = ResearchEngine.duckDuckGoSearch,
        fetchPage: @escaping @Sendable (String) async -> String = ResearchEngine.fetchAndStripHTML
    ) {
        self.reportsDirectory = reportsDirectory
        self.search = search
        self.fetchPage = fetchPage
    }

    static let defaultReportsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Aria Notes/Research", isDirectory: true)

    func research(
        topic: String,
        maxSources: Int = 3,
        synthesize: @Sendable (String) async throws -> String
    ) async -> ResearchOutcome {
        // 1. Two concurrent searches
        async let results1 = search(topic)
        async let results2 = search("\(topic) explained")
        let (r1, r2) = await (results1, results2)

        // 2. Merge + dedupe by URL, take first maxSources
        var seenURLs = Set<String>()
        var merged: [SearchResult] = []
        for result in (r1 + r2) {
            if seenURLs.insert(result.url).inserted {
                merged.append(result)
                if merged.count >= maxSources { break }
            }
        }

        // 3. Fetch pages concurrently (up to 3)
        let fetchTargets = Array(merged.prefix(3))
        var pageContents: [(url: String, content: String)] = []

        if fetchTargets.count >= 3 {
            async let c1 = fetchPage(fetchTargets[0].url)
            async let c2 = fetchPage(fetchTargets[1].url)
            async let c3 = fetchPage(fetchTargets[2].url)
            let (p1, p2, p3) = await (c1, c2, c3)
            pageContents = [
                (fetchTargets[0].url, p1),
                (fetchTargets[1].url, p2),
                (fetchTargets[2].url, p3)
            ]
        } else if fetchTargets.count == 2 {
            async let c1 = fetchPage(fetchTargets[0].url)
            async let c2 = fetchPage(fetchTargets[1].url)
            let (p1, p2) = await (c1, c2)
            pageContents = [
                (fetchTargets[0].url, p1),
                (fetchTargets[1].url, p2)
            ]
        } else if fetchTargets.count == 1 {
            let p1 = await fetchPage(fetchTargets[0].url)
            pageContents = [(fetchTargets[0].url, p1)]
        }

        // 4. Build synthesis prompt
        var sourceParts: [String] = []
        for (idx, item) in pageContents.enumerated() {
            sourceParts.append("Source \(idx + 1) [\(item.url)]: \(item.content.prefix(1500))")
        }

        let prompt = """
        Write a structured research report on: \(topic)
        Include: executive summary, 3-4 content sections with headings, key findings.
        Return ONLY JSON: {"sections":[{"heading":"...","content":"..."}],"keyFindings":["..."]}

        \(sourceParts.joined(separator: "\n"))
        """

        let usedSources = pageContents.map { $0.url }

        // 5. Parse → ResearchReport
        let report: ResearchReport
        do {
            let raw = try await synthesize(prompt)
            report = parseReport(raw: raw, topic: topic, sources: usedSources)
        } catch {
            // Fallback: build report from raw snippets
            let fallbackSections: [ReportSection]
            if pageContents.isEmpty {
                fallbackSections = [ReportSection(heading: "Research Notes", content: "No sources found for '\(topic)'.")]
            } else {
                let notes = pageContents.map { "\($0.url):\n\($0.content.prefix(500))" }.joined(separator: "\n\n")
                fallbackSections = [ReportSection(heading: "Research Notes", content: notes)]
            }
            report = ResearchReport(
                id: UUID(),
                topic: topic,
                date: Date(),
                sections: fallbackSections,
                keyFindings: [],
                sources: usedSources
            )
        }

        // 6. Save
        return ResearchOutcome(report: report, savedURL: saveReport(report, topic: topic))
    }

    // MARK: - DuckDuckGo scraper

    static func duckDuckGoSearch(_ query: String) async -> [SearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else {
            return []
        }
        return parseDuckDuckGoHTML(html)
    }

    // MARK: - HTML fetcher

    static func fetchAndStripHTML(_ urlString: String) async -> String {
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let html = String(data: data, encoding: .utf8) else {
            return ""
        }
        // Strip HTML tags
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // Collapse whitespace
        let collapsed = stripped.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(2000))
    }

    // MARK: - Private helpers

    private func parseReport(raw: String, topic: String, sources: [String]) -> ResearchReport {
        guard let startIdx = raw.firstIndex(of: "{"),
              let endIdx = raw.lastIndex(of: "}") else {
            return fallbackReport(topic: topic, sources: sources, rawNote: raw)
        }
        let jsonString = String(raw[startIdx...endIdx])
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallbackReport(topic: topic, sources: sources, rawNote: raw)
        }

        var sections: [ReportSection] = []
        if let sectionArray = obj["sections"] as? [[String: Any]] {
            for item in sectionArray {
                guard let heading = item["heading"] as? String,
                      let content = item["content"] as? String else { continue }
                sections.append(ReportSection(heading: heading, content: content))
            }
        }

        let keyFindings = obj["keyFindings"] as? [String] ?? []

        if sections.isEmpty {
            return fallbackReport(topic: topic, sources: sources, rawNote: raw)
        }

        return ResearchReport(
            id: UUID(),
            topic: topic,
            date: Date(),
            sections: sections,
            keyFindings: keyFindings,
            sources: sources
        )
    }

    private func fallbackReport(topic: String, sources: [String], rawNote: String) -> ResearchReport {
        ResearchReport(
            id: UUID(),
            topic: topic,
            date: Date(),
            sections: [ReportSection(heading: "Research Notes", content: rawNote)],
            keyFindings: [],
            sources: sources
        )
    }

    private func saveReport(_ report: ResearchReport, topic: String) -> URL? {
        let dateStr = ISO8601DateFormatter().string(from: report.date).prefix(10)
        let safeTopic = topic
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ")).inverted)
            .joined()
            .replacingOccurrences(of: " ", with: "-")
        let filename = "\(dateStr)-\(safeTopic).json"
        let destination = reportsDirectory.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(
                at: reportsDirectory,
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(report).write(to: destination, options: .atomic)
            return destination
        } catch {
            Log.trace("research: report save failed")
            return nil
        }
    }
}

// MARK: - HTML parser (free function for testability)

private func parseDuckDuckGoHTML(_ html: String) -> [SearchResult] {
    var results: [SearchResult] = []

    // Simple line-by-line scan for result__a and result__snippet
    // Pattern: <a class="result__a" href="...">title</a>
    let lines = html.components(separatedBy: "\n")
    var titles: [String] = []
    var urls: [String] = []
    var snippets: [String] = []

    for line in lines {
        if line.contains("result__a") {
            if let href = extractAttribute("href", from: line) {
                urls.append(href)
            }
            let text = stripTags(line)
            if !text.isEmpty {
                titles.append(text)
            }
        }
        if line.contains("result__snippet") {
            let text = stripTags(line)
            snippets.append(text)
        }
    }

    let count = min(min(titles.count, urls.count), 5)
    for i in 0..<count {
        let snippet = i < snippets.count ? snippets[i] : ""
        results.append(SearchResult(title: titles[i], url: urls[i], snippet: snippet))
    }
    return results
}

private func extractAttribute(_ attr: String, from html: String) -> String? {
    let pattern = "\(attr)=\"([^\"]+)\""
    guard let range = html.range(of: pattern, options: .regularExpression) else { return nil }
    let match = String(html[range])
    let inner = match.dropFirst(attr.count + 2).dropLast(1)
    return String(inner)
}

private func stripTags(_ html: String) -> String {
    let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
}
