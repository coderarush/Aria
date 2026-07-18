import SwiftUI

/// Shared state for things Aria draws ON your screen (as opposed to her own HUD):
/// guidance markers ("here's the button") she pools onto a located element, and
/// the worker blobs she spawns while running agentic work. The `AriaStageController`
/// renders this in a passive, click-through overlay; tools and the controller
/// mutate it. Coordinates are TOP-LEFT global screen points (CGEvent space), the
/// same space `VisionLocator.screenPoint` returns.
@MainActor
final class AriaStage: ObservableObject {
    static let shared = AriaStage()

    /// A blob Aria pools onto a point to point something out, optionally labeled.
    struct Marker: Identifiable, Equatable {
        let id: UUID
        var point: CGPoint
        var label: String?
        var colorHex: String      // resolved to Color in the view (Color isn't Equatable-friendly across actors)
        var bornAt: Date
    }

    /// A small sub-agent blob, shown while parallel/agentic work runs.
    struct Worker: Identifiable, Equatable {
        let id: UUID
        var label: String
    }

    @Published private(set) var markers: [Marker] = []
    @Published private(set) var workers: [Worker] = []
    /// Where the workers cluster before they scatter — the HUD blob center, in
    /// top-left screen points. Nil ⇒ bottom-right default.
    @Published var workerAnchor: CGPoint? = nil

    var isActive: Bool { !markers.isEmpty || !workers.isEmpty }

    // MARK: Guidance markers

    /// Pool a guidance blob onto `point`. Auto-expires after `ttl` so the screen
    /// never accumulates stale marks. Returns the id (for manual `clear`).
    @discardableResult
    func point(at point: CGPoint, label: String? = nil, colorHex: String = "#6C7CF0", ttl: TimeInterval = 7, now: Date = Date()) -> UUID {
        let m = Marker(id: UUID(), point: point, label: label, colorHex: colorHex, bornAt: now)
        markers.append(m)
        let id = m.id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ttl * 1_000_000_000))
            self?.markers.removeAll { $0.id == id }
        }
        return id
    }

    func clearMarkers() { markers.removeAll() }

    // MARK: Worker swarm

    /// Show `count` worker blobs (clamped 0…8) clustered at `anchor`. Replaces the
    /// current swarm — call with 0 to dismiss.
    func setWorkers(count: Int, labels: [String] = [], anchor: CGPoint? = nil) {
        if let anchor { workerAnchor = anchor }
        let n = max(0, min(count, 8))
        if n == workers.count { return }
        if n == 0 { workers.removeAll(); return }
        var next = workers
        while next.count < n {
            let i = next.count
            next.append(Worker(id: UUID(), label: i < labels.count ? labels[i] : "worker \(i + 1)"))
        }
        if next.count > n { next.removeLast(next.count - n) }
        workers = next
    }

    func clearWorkers() { workers.removeAll() }
}
