import Foundation

/// A reference to a work artifact — never a copy of its contents.
struct Artifact: Equatable, Sendable {
    enum Kind: String, Sendable { case repo, doc, file, commit, export, decision, session }
    let kind: Kind
    let id: String        // natural key: path, commit sha, session timestamp …
    let label: String
    let project: String?
    let date: Date?
}

/// ArtifactGraph (Phase 5): an INDEX over the artifacts the user produces —
/// docs, commits, files, exports, decisions, sessions. It is **not storage**:
/// it owns nothing, holds no copies, and adds no persistence. Artifacts are
/// pulled lazily from the sources that already have them (KnowledgeIndex,
/// SessionMemory, git) via injected providers, then merged, deduped, and ranked
/// on read. It does not duplicate UnifiedRecall's content search — this is a
/// reference index ("open latest", "find related", "continue artifact").
struct ArtifactGraph {
    typealias Provider = @Sendable () async -> [Artifact]

    private let providers: [Provider]

    init(providers: [Provider]) { self.providers = providers }

    /// All artifacts, deduped by (kind,id), newest first.
    func all() async -> [Artifact] {
        var seen = Set<String>()
        var out: [Artifact] = []
        for provider in providers {
            for art in await provider() where seen.insert("\(art.kind.rawValue)|\(art.id)").inserted {
                out.append(art)
            }
        }
        return out.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Most recent artifact, optionally of one kind — "open latest".
    func latest(kind: Artifact.Kind? = nil) async -> Artifact? {
        await all().first { kind == nil || $0.kind == kind }
    }

    /// Artifacts related to `anchor` — same project, or within `within` of its
    /// timestamp. "Find related" / "continue artifact".
    func related(to anchor: Artifact, within: TimeInterval = 7 * 86_400) async -> [Artifact] {
        await all().filter { other in
            guard !(other.kind == anchor.kind && other.id == anchor.id) else { return false }
            if let p = anchor.project?.lowercased(), let op = other.project?.lowercased(), p == op { return true }
            if let d = anchor.date, let od = other.date, abs(d.timeIntervalSince(od)) <= within { return true }
            return false
        }
    }

    /// Artifacts whose label matches `query`.
    func find(_ query: String) async -> [Artifact] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return await all().filter { $0.label.lowercased().contains(q) }
    }

    /// Live index over the existing sources. No git/file providers yet — docs and
    /// sessions are the durable, already-indexed sources today.
    static func live(sessions: SessionMemoryStore = .shared,
                     knowledge: KnowledgeIndex = .shared,
                     now: @escaping @Sendable () -> Date = Date.init) -> ArtifactGraph {
        ArtifactGraph(providers: [
            { (await knowledge.recentDocuments(limit: 50)).map {
                Artifact(kind: .doc, id: $0.path, label: $0.title, project: nil, date: $0.mtime)
            } },
            { (await sessions.active(now: now())).map {
                Artifact(kind: .session, id: String($0.date.timeIntervalSince1970),
                         label: $0.goal, project: $0.project, date: $0.date)
            } },
        ])
    }
}
