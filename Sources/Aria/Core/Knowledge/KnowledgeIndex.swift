import Foundation

/// One indexed document: path, title, modification time, and its text chunks.
struct IndexedDocument: Codable, Equatable, Sendable {
    let path: String
    let title: String
    let mtime: Date
    let chunks: [String]
}

/// A search result the model (and the user) can act on.
struct KnowledgeHit: Codable, Equatable, Sendable {
    let path: String
    let title: String
    let snippet: String
    let score: Double
}

struct IndexStats: Equatable, Sendable {
    var indexed = 0      // files (re)extracted this pass
    var skipped = 0      // unchanged, kept as-is
    var removed = 0      // disappeared from disk
    var failed = 0       // unreadable/unsupported
}

/// The Local Knowledge Engine's store: incremental, privacy-first index of the
/// user's chosen folders (V9 constitution strategic priority — "users should be
/// able to naturally query their own knowledge"). Everything stays on disk
/// locally; nothing is sent anywhere.
///
/// Retrieval is lexical (term frequency + title boost) — deterministic, fast,
/// zero model dependency. An embedding upgrade can replace `score(_:)` behind
/// the same `search` interface later.
actor KnowledgeIndex {
    static let shared = KnowledgeIndex()

    private let storeURL: URL
    private var documents: [String: IndexedDocument]   // keyed by path

    init(storeURL: URL? = nil) {
        let url = storeURL ?? PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("knowledge.json")
        self.storeURL = url
        self.documents = Self.load(from: url)
    }

    var documentCount: Int { documents.count }

    // MARK: Indexing

    /// Walk the folders, (re)extract changed files, drop deleted ones.
    /// Incremental: unchanged mtime = skip. Hidden dirs, bundles, node_modules,
    /// and .git are never entered.
    @discardableResult
    func reindex(folders: [String]) async -> IndexStats {
        var stats = IndexStats()
        var seen = Set<String>()
        let fm = FileManager.default

        for folder in folders {
            let root = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
            guard let walker = fm.enumerator(at: root,
                                             includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walker {
                let name = url.lastPathComponent
                if name == "node_modules" || name == ".git" || name == ".build" {
                    walker.skipDescendants(); continue
                }
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true,
                      TextExtractor.isIndexable(url) else { continue }
                let path = url.path
                guard path != storeURL.path else { continue }   // never index our own store
                seen.insert(path)
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if let existing = documents[path], existing.mtime == mtime {
                    stats.skipped += 1
                    continue
                }
                guard let text = TextExtractor.extract(from: url) else {
                    stats.failed += 1
                    documents[path] = nil
                    continue
                }
                let title = url.deletingPathExtension().lastPathComponent
                documents[path] = IndexedDocument(path: path, title: title, mtime: mtime,
                                                  chunks: Chunker.chunks(of: text))
                stats.indexed += 1
            }
        }

        // Drop documents whose files vanished (only within the indexed folders).
        // Canonicalize both sides: the enumerator yields /private/var/… while
        // user-supplied paths may say /var/… (symlinked) — realpath unifies them.
        let roots = folders.map { Self.canonical(($0 as NSString).expandingTildeInPath) + "/" }
        for (path, _) in documents where !seen.contains(path) {
            let canon = Self.canonical(path)
            if roots.contains(where: { canon.hasPrefix($0) }) {
                documents[path] = nil
                stats.removed += 1
            }
        }
        save()
        return stats
    }

    /// realpath()-based canonical form; falls back to the input when the path
    /// no longer exists (deleted files still need their PARENT canonicalized,
    /// so resolve the deepest existing ancestor and re-append the remainder).
    static func canonical(_ path: String) -> String {
        if let r = realpath(path, nil) {
            defer { free(r) }
            return String(cString: r)
        }
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        if parent != path, let r = realpath(parent, nil) {
            defer { free(r) }
            return String(cString: r) + "/" + url.lastPathComponent
        }
        return path
    }

    /// Forget everything (privacy: one obvious clear-all).
    func clear() {
        documents = [:]
        save()
    }

    // MARK: Search

    func search(_ query: String, limit: Int = 5) -> [KnowledgeHit] {
        let terms = Self.terms(query)
        guard !terms.isEmpty else { return [] }

        var hits: [KnowledgeHit] = []
        for doc in documents.values {
            let titleTerms = Self.terms(doc.title)
            var bestChunk = ""
            var bestScore = 0.0
            for chunk in doc.chunks {
                let s = Self.score(terms: terms, chunk: chunk)
                if s > bestScore { bestScore = s; bestChunk = chunk }
            }
            // Title boost: every query term that appears in the title counts double.
            let titleBoost = Double(terms.filter { t in titleTerms.contains(where: { $0.hasPrefix(t) || t.hasPrefix($0) }) }.count) * 2.0
            let total = bestScore + titleBoost
            guard total > 0 else { continue }
            hits.append(KnowledgeHit(path: doc.path, title: doc.title,
                                     snippet: Self.snippet(of: bestChunk.isEmpty ? doc.chunks.first ?? "" : bestChunk),
                                     score: total))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Lowercased terms, stopwords removed.
    static func terms(_ text: String) -> [String] {
        let stop: Set<String> = ["the", "a", "an", "of", "to", "in", "on", "and", "or",
                                 "what", "did", "say", "about", "is", "are", "was", "my",
                                 "me", "for", "with", "do", "does", "how", "this", "that"]
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stop.contains($0) }
    }

    private static func score(terms: [String], chunk: String) -> Double {
        let c = chunk.lowercased()
        var s = 0.0
        for t in terms where c.contains(t) {
            s += 1.0
        }
        return s
    }

    private static func snippet(of chunk: String, max: Int = 240) -> String {
        let flat = chunk.replacingOccurrences(of: "\n", with: " ")
        guard flat.count > max else { return flat }
        return String(flat.prefix(max)) + "…"
    }

    // MARK: Persistence

    private func save() {
        let encoder = JSONEncoder()
        // Epoch seconds, NOT iso8601: iso8601 drops fractional seconds, which
        // would make every stored mtime != the on-disk mtime after a relaunch
        // and silently defeat incremental indexing.
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(Array(documents.values)) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [String: IndexedDocument] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let docs = (try? decoder.decode([IndexedDocument].self, from: data)) ?? []
        return Dictionary(uniqueKeysWithValues: docs.map { ($0.path, $0) })
    }
}
