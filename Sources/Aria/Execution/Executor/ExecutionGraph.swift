import Foundation

/// A directed acyclic graph of actions (spec §17).
///
/// Nodes are ``Domain/Action`` values; edges are dependencies (a prerequisite
/// must complete before its dependent becomes ready). Supports ready-set
/// queries for parallel scheduling, topological ordering, and cycle detection.
/// Dynamic insertion is just another `addAction` before/while executing.
struct ExecutionGraph {

    enum GraphError: Error { case cycleDetected }

    private(set) var nodes: [UUID: Domain.Action] = [:]
    /// node id -> set of prerequisite node ids
    private(set) var dependencies: [UUID: Set<UUID>] = [:]

    init() {}

    /// Insert (or replace) an action and record the ids it depends on.
    mutating func addAction(_ action: Domain.Action, dependsOn: [UUID] = []) {
        nodes[action.id] = action
        dependencies[action.id] = Set(dependsOn)
    }

    /// Actions whose dependencies are all in `completed` and which are not
    /// themselves completed — i.e. the set safe to dispatch right now.
    func readyNodes(completed: Set<UUID>) -> [Domain.Action] {
        nodes.values.filter { node in
            !completed.contains(node.id)
                && (dependencies[node.id] ?? []).isSubset(of: completed)
        }
    }

    /// A valid execution order (dependencies before dependents) via Kahn's
    /// algorithm. Throws ``GraphError/cycleDetected`` if no such order exists.
    func topologicalOrder() throws -> [UUID] {
        var inDegree: [UUID: Int] = [:]
        for id in nodes.keys { inDegree[id] = dependencies[id]?.count ?? 0 }

        var dependents: [UUID: [UUID]] = [:]
        for (node, deps) in dependencies {
            for dep in deps { dependents[dep, default: []].append(node) }
        }

        var queue = inDegree.filter { $0.value == 0 }.map(\.key)
        var order: [UUID] = []
        while !queue.isEmpty {
            let n = queue.removeFirst()
            order.append(n)
            for m in dependents[n] ?? [] {
                inDegree[m, default: 0] -= 1
                if inDegree[m] == 0 { queue.append(m) }
            }
        }

        guard order.count == nodes.count else { throw GraphError.cycleDetected }
        return order
    }

    /// True when the graph contains a dependency cycle.
    var hasCycle: Bool { (try? topologicalOrder()) == nil }
}
