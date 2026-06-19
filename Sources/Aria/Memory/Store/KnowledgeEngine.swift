import Foundation

/// A node in the knowledge graph (spec §82).
struct KnowledgeNode: Identifiable, Sendable {
    enum Kind: String, Sendable { case project, objective, artifact }
    let id: UUID
    let kind: Kind
    var label: String

    init(id: UUID = UUID(), kind: Kind, label: String) {
        self.id = id
        self.kind = kind
        self.label = label
    }
}

/// A directed relation between two nodes.
struct KnowledgeEdge: Sendable {
    let from: UUID
    let to: UUID
    let relation: String
}

/// The local knowledge graph (spec §82): projects, objectives, artifacts and
/// their relations. Link/merge/retrieve/summarize only — no internet crawling,
/// no autonomous discovery.
actor KnowledgeEngine {

    private var nodes: [UUID: KnowledgeNode] = [:]
    private var edges: [KnowledgeEdge] = []

    func add(_ node: KnowledgeNode) { nodes[node.id] = node }

    func allNodes() -> [KnowledgeNode] { Array(nodes.values) }

    func link(from: UUID, to: UUID, relation: String) {
        edges.append(KnowledgeEdge(from: from, to: to, relation: relation))
    }

    /// Nodes directly reachable from `id`.
    func neighbors(of id: UUID) -> [KnowledgeNode] {
        edges.filter { $0.from == id }.compactMap { nodes[$0.to] }
    }

    func summarize(_ id: UUID) -> String {
        guard let node = nodes[id] else { return "" }
        let count = edges.filter { $0.from == id }.count
        return "\(node.label) (\(node.kind.rawValue)): \(count) related"
    }

    /// Fold one node into another, repointing its edges (spec §82 merge).
    func merge(_ source: UUID, into target: UUID) {
        edges = edges.map { edge in
            KnowledgeEdge(from: edge.from == source ? target : edge.from,
                          to: edge.to == source ? target : edge.to,
                          relation: edge.relation)
        }
        nodes[source] = nil
    }
}
