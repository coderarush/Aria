import Foundation

/// A node in the memory graph: a *reference* into an existing store, never a copy
/// of its data. `id` is the natural key (goal id, session timestamp, project
/// name, event signature); `label` is a human title for display.
struct GraphNode: Hashable, Sendable {
    enum Kind: String, Sendable { case goal, session, timelineEvent, artifact, decision, project }
    let kind: Kind
    let id: String
    let label: String

    static func goal(_ g: Goal) -> GraphNode { .init(kind: .goal, id: g.id, label: g.title) }
    static func session(_ s: SessionSnapshot) -> GraphNode {
        .init(kind: .session, id: String(s.date.timeIntervalSince1970), label: s.goal)
    }
    static func project(_ name: String) -> GraphNode {
        .init(kind: .project, id: name.lowercased(), label: name)
    }
    static func timelineEvent(_ e: TimelineEntry) -> GraphNode {
        .init(kind: .timelineEvent, id: "\(e.kind.rawValue)|\(e.title)|\(e.date.timeIntervalSince1970)", label: e.title)
    }
    static func decision(id: String, label: String) -> GraphNode { .init(kind: .decision, id: id, label: label) }
    static func artifact(id: String, label: String) -> GraphNode { .init(kind: .artifact, id: id, label: label) }
}

enum GraphRelation: String, Sendable {
    case inProject       // goal/session → project
    case hasSession      // goal ↔ session
    case producedEvent   // goal/session → timelineEvent
    case producedArtifact// goal → artifact
    case motivates       // decision → goal
    case relatedTo       // generic explicit link
}

/// One relationship. Every edge is explainable: where it came from (`source`),
/// why it holds (`reason`), and how sure we are (`confidence`, 0…1).
struct GraphEdge: Equatable, Sendable {
    let from: GraphNode
    let to: GraphNode
    let relation: GraphRelation
    let source: String
    let reason: String
    let confidence: Double
}

/// MemoryGraph (Phase 12): the relationship layer. It is **NOT storage** — it
/// holds no events, goals, or sessions of its own. Nodes are references into the
/// stores that already own the data (GoalEngine, SessionMemory, TimelineEngine);
/// edges are *derived lazily on query* from those stores' natural keys, plus any
/// explicit links a caller adds (kept in-memory only, never persisted). Because
/// derivation reads the durable stores, the graph rebuilds itself across launches
/// with no second copy to keep in sync.
///
/// Traversal is bounded and deterministic: depth ≤ 3, fan-out capped, a visited
/// set kills cycles, and edges sort by confidence so results are stable.
actor MemoryGraph {
    static let shared = MemoryGraph()

    private let goals: GoalEngine
    private let sessions: SessionMemoryStore
    private let timeline: TimelineEngine
    private let fanoutCap: Int
    private let nodeCap: Int
    static let maxDepth = 3

    /// Explicit edges added via `link` — process-lifetime only, bounded. Durable
    /// relationships come from the stores, so these are the *extra* ones a caller
    /// asserts (e.g. decision → goal) before ArtifactGraph exists.
    private var explicit: [GraphEdge] = []
    private let explicitCap = 2_000

    init(goals: GoalEngine = .shared,
         sessions: SessionMemoryStore = .shared,
         timeline: TimelineEngine = .shared,
         fanoutCap: Int = 12,
         nodeCap: Int = 300) {
        self.goals = goals
        self.sessions = sessions
        self.timeline = timeline
        self.fanoutCap = fanoutCap
        self.nodeCap = nodeCap
    }

    // MARK: link

    /// Assert an explicit relationship (in-memory only). Dedupes by (from,to,
    /// relation), keeping the strongest confidence.
    func link(_ from: GraphNode, _ to: GraphNode, relation: GraphRelation,
              reason: String, confidence: Double) {
        let edge = GraphEdge(from: from, to: to, relation: relation,
                             source: "explicit link", reason: reason,
                             confidence: min(1, max(0, confidence)))
        if let i = explicit.firstIndex(where: { $0.from == from && $0.to == to && $0.relation == relation }) {
            if edge.confidence > explicit[i].confidence { explicit[i] = edge }
            return
        }
        explicit.append(edge)
        if explicit.count > explicitCap { explicit.removeFirst(explicit.count - explicitCap) }
    }

    // MARK: neighbors

    /// Incident edges of `node` (derived + explicit), deduped by (to, relation),
    /// filtered by `minConfidence`, sorted confidence-desc, capped at `fanoutCap`.
    func neighbors(of node: GraphNode, minConfidence: Double = 0, now: Date = Date()) async -> [GraphEdge] {
        var edges = await derived(of: node, now: now)
        edges += explicit.filter { $0.from == node }
        return finalize(edges, minConfidence: minConfidence)
    }

    // MARK: related (bounded BFS)

    /// Distinct nodes reachable from `start` within `depth` hops (clamped to
    /// `maxDepth`). Deterministic, cycle-safe, capped at `nodeCap`.
    func related(to start: GraphNode, depth: Int = 2, minConfidence: Double = 0,
                 now: Date = Date()) async -> [GraphNode] {
        let limit = min(max(0, depth), Self.maxDepth)
        var visited: Set<GraphNode> = [start]
        var frontier = [start]
        var out: [GraphNode] = []
        var hop = 0
        while hop < limit, !frontier.isEmpty, out.count < nodeCap {
            var next: [GraphNode] = []
            for node in frontier {
                for edge in await neighbors(of: node, minConfidence: minConfidence, now: now) {
                    guard visited.insert(edge.to).inserted else { continue }
                    out.append(edge.to)
                    next.append(edge.to)
                    if out.count >= nodeCap { break }
                }
                if out.count >= nodeCap { break }
            }
            frontier = next
            hop += 1
        }
        return out
    }

    // MARK: explain

    /// The relationship between two nodes (source/reason/confidence), or nil.
    func explain(_ from: GraphNode, _ to: GraphNode, now: Date = Date()) async -> GraphEdge? {
        await neighbors(of: from, now: now).first { $0.to == to }
    }

    // MARK: trace ("what led to this")

    /// Provenance edges reachable from `node` within `depth` — the chain that led
    /// here. Deterministic BFS over edges, cycle-safe, bounded.
    func trace(from node: GraphNode, depth: Int = 3, minConfidence: Double = 0,
               now: Date = Date()) async -> [GraphEdge] {
        let limit = min(max(0, depth), Self.maxDepth)
        var visited: Set<GraphNode> = [node]
        var frontier = [node]
        var out: [GraphEdge] = []
        var hop = 0
        while hop < limit, !frontier.isEmpty, out.count < nodeCap {
            var next: [GraphNode] = []
            for n in frontier {
                for edge in await neighbors(of: n, minConfidence: minConfidence, now: now) {
                    out.append(edge)
                    if visited.insert(edge.to).inserted { next.append(edge.to) }
                    if out.count >= nodeCap { break }
                }
                if out.count >= nodeCap { break }
            }
            frontier = next
            hop += 1
        }
        return out
    }

    // MARK: derivation (lazy, read-only over the stores)

    private func derived(of node: GraphNode, now: Date) async -> [GraphEdge] {
        switch node.kind {
        case .goal:        return await goalEdges(node, now: now)
        case .session:     return await sessionEdges(node, now: now)
        case .project:     return await projectEdges(node, now: now)
        case .timelineEvent, .artifact, .decision:
            // No store provider yet (artifacts/decisions arrive with ArtifactGraph);
            // these participate only through explicit links.
            return []
        }
    }

    private func goalEdges(_ node: GraphNode, now: Date) async -> [GraphEdge] {
        guard let g = await goals.goal(id: node.id) else { return [] }
        let gn = GraphNode.goal(g)
        var es: [GraphEdge] = []
        if let p = g.project, !p.isEmpty {
            es.append(GraphEdge(from: gn, to: .project(p), relation: .inProject,
                                source: "goal.project field",
                                reason: "‘\(g.title)’ belongs to project \(p)", confidence: 1.0))
        }
        for snap in await sessions.active(now: now) {
            let c = Self.titleProjectMatch(goalTitle: g.title, goalProject: g.project, snap: snap)
            if c > 0 {
                es.append(GraphEdge(from: gn, to: .session(snap), relation: .hasSession,
                                    source: "title/project match",
                                    reason: "session ‘\(snap.goal)’ matches this goal",
                                    confidence: c))
            }
        }
        for e in await goalEvents(g, now: now) {
            es.append(GraphEdge(from: gn, to: .timelineEvent(e), relation: .producedEvent,
                                source: "timeline",
                                reason: "\(e.kind.rawValue) for ‘\(g.title)’", confidence: 0.95))
        }
        return es
    }

    private func sessionEdges(_ node: GraphNode, now: Date) async -> [GraphEdge] {
        guard let snap = await sessions.active(now: now).first(where: {
            String($0.date.timeIntervalSince1970) == node.id
        }) else { return [] }
        let sn = GraphNode.session(snap)
        var es: [GraphEdge] = []
        if let p = snap.project, !p.isEmpty {
            es.append(GraphEdge(from: sn, to: .project(p), relation: .inProject,
                                source: "session.project field",
                                reason: "session is in project \(p)", confidence: 1.0))
        }
        for g in await goals.all() {
            let c = Self.titleProjectMatch(goalTitle: g.title, goalProject: g.project, snap: snap)
            if c > 0 {
                es.append(GraphEdge(from: sn, to: .goal(g), relation: .hasSession,
                                    source: "title/project match",
                                    reason: "this session advances ‘\(g.title)’", confidence: c))
            }
        }
        // Events near the session, same project — time+project proximity.
        let window: TimeInterval = 6 * 3600
        for e in await timeline.events(from: snap.date.addingTimeInterval(-window),
                                       to: snap.date.addingTimeInterval(window), now: now) {
            guard e.kind == .taskFinished || e.kind == .testRun || e.kind == .commitCreated else { continue }
            guard snap.project == nil || e.project?.lowercased() == snap.project?.lowercased() else { continue }
            es.append(GraphEdge(from: sn, to: .timelineEvent(e), relation: .producedEvent,
                                source: "time+project proximity",
                                reason: "‘\(e.title)’ happened during this session", confidence: 0.6))
        }
        return es
    }

    private func projectEdges(_ node: GraphNode, now: Date) async -> [GraphEdge] {
        let pn = node
        var es: [GraphEdge] = []
        for g in await goals.all() where g.project?.lowercased() == node.id {
            es.append(GraphEdge(from: pn, to: .goal(g), relation: .inProject,
                                source: "goal.project field",
                                reason: "‘\(g.title)’ is in this project", confidence: 1.0))
        }
        for snap in await sessions.active(now: now) where snap.project?.lowercased() == node.id {
            es.append(GraphEdge(from: pn, to: .session(snap), relation: .inProject,
                                source: "session.project field",
                                reason: "session ‘\(snap.goal)’ is in this project", confidence: 1.0))
        }
        return es
    }

    /// Goal lifecycle events from the timeline (created/advanced), by title.
    private func goalEvents(_ g: Goal, now: Date) async -> [TimelineEntry] {
        await timeline.events(from: g.createdAt.addingTimeInterval(-1),
                              to: max(g.updatedAt, now).addingTimeInterval(1), now: now)
            .filter { ($0.kind == .goalCreated || $0.kind == .goalAdvanced) && $0.title == g.title }
    }

    // MARK: helpers

    static func titleProjectMatch(goalTitle: String, goalProject: String?, snap: SessionSnapshot) -> Double {
        let gt = goalTitle.lowercased(), st = snap.goal.lowercased()
        if gt == st { return 0.9 }
        if !gt.isEmpty && (st.contains(gt) || gt.contains(st)) { return 0.7 }
        if let gp = goalProject?.lowercased(), let sp = snap.project?.lowercased(), gp == sp { return 0.6 }
        return 0
    }

    /// Dedupe by (to, relation) keeping strongest, filter, sort, cap fan-out.
    private func finalize(_ edges: [GraphEdge], minConfidence: Double) -> [GraphEdge] {
        var best: [String: GraphEdge] = [:]
        for e in edges where e.confidence >= minConfidence {
            let key = "\(e.to.kind.rawValue)|\(e.to.id)|\(e.relation.rawValue)"
            if let cur = best[key], cur.confidence >= e.confidence { continue }
            best[key] = e
        }
        let sorted = best.values.sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            if $0.to.kind != $1.to.kind { return $0.to.kind.rawValue < $1.to.kind.rawValue }
            return $0.to.id < $1.to.id
        }
        return Array(sorted.prefix(fanoutCap))
    }
}
