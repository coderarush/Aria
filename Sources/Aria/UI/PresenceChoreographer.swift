import SwiftUI

/// Drives the timed transitions between Aria's presence modes. It is fed the
/// target `PresenceMode` (derived from the island state) plus the TimelineView
/// clock, and walks through the choreography:
///
///   hidden → (borderIn) → border
///   border → (consolidating) → blob          // water pooling into a droplet
///   blob   → (splashing → igniting) → border // droplet falls, rim ignites
///   *      → (dismissing) → hidden
///
/// Sequencing math is timestamp-injected so it can be unit-tested without a
/// render loop. Transitions always run to their settled phase before reconciling
/// toward a newer target — they're sub-second, so no mid-flight reversal needed.
@MainActor
final class PresenceChoreographer: ObservableObject {

    enum Kind { case hidden, borderIn, border, consolidating, blob, splashing, igniting, dismissing }

    enum Phase: Equatable {
        case hidden
        case borderIn(Double)       // 0→1
        case border
        case consolidating(Double)  // 0→1  border drains, blob pools
        case blob
        case splashing(Double)      // 0→1  blob falls to the bottom edge
        case igniting(Double)       // 0→1  rim lights from bottom-center outward
        case dismissing(Double)     // 0→1

        var kind: Kind {
            switch self {
            case .hidden: return .hidden
            case .borderIn: return .borderIn
            case .border: return .border
            case .consolidating: return .consolidating
            case .blob: return .blob
            case .splashing: return .splashing
            case .igniting: return .igniting
            case .dismissing: return .dismissing
            }
        }
        /// 0…1 progress of a timed phase (settled phases report 0).
        var progress: Double {
            switch self {
            case let .borderIn(p), let .consolidating(p), let .splashing(p),
                 let .igniting(p), let .dismissing(p): return p
            case .hidden, .border, .blob: return 0
            }
        }
    }

    @Published private(set) var phase: Phase = .hidden

    static let dBorderIn = 0.45
    static let dConsolidate = 0.7
    static let dSplash = 0.35
    static let dIgnite = 0.5
    static let dDismiss = 0.3

    private var target: PresenceMode = .hidden
    private var start: Double = 0   // timestamp the current timed phase began

    /// React to a new desired mode. No-op while a transition toward the same
    /// target is already in flight.
    func setMode(_ mode: PresenceMode, now: Double) {
        guard mode != target else { return }
        if mode == .hidden {
            // Remember whether we're fading out of a lit rim so the dismiss fades it.
            phaseWasBorder = [.border, .borderIn, .igniting].contains(phase.kind)
        }
        target = mode
        reconcile(now: now)
    }

    /// Advance timed phases on each clock tick; chain/settle when one completes.
    func advance(now: Double) {
        let dur = duration(of: phase.kind)
        guard dur > 0 else { reconcile(now: now); return }
        let p = min(1, max(0, (now - start) / dur))
        if p >= 1 {
            settle(now: now)
        } else {
            phase = withProgress(phase.kind, p)
        }
    }

    // MARK: - Transition logic (pure-ish; drives the table above)

    private func reconcile(now: Double) {
        switch phase.kind {
        case .borderIn, .consolidating, .splashing, .igniting, .dismissing:
            return  // a transition owns the timeline until it settles
        case .hidden:
            switch target {
            case .hidden: break
            case .border: begin(.borderIn, now)
            case .blob:   phase = .blob          // pop in directly (suggestion / instant blob)
            }
        case .border:
            switch target {
            case .border: break
            case .blob:   begin(.consolidating, now)
            case .hidden: begin(.dismissing, now)
            }
        case .blob:
            switch target {
            case .blob: break
            case .border: begin(.splashing, now)
            case .hidden: begin(.dismissing, now)
            }
        }
    }

    /// Called when a timed phase reaches 1.0.
    private func settle(now: Double) {
        switch phase.kind {
        case .borderIn:      phase = .border;            reconcile(now: now)
        case .consolidating: phase = .blob;              reconcile(now: now)
        case .splashing:     begin(.igniting, now)       // splash always chains into ignite
        case .igniting:      phase = .border;            reconcile(now: now)
        case .dismissing:    phase = .hidden;            reconcile(now: now)
        case .hidden, .border, .blob: break
        }
    }

    private func begin(_ kind: Kind, _ now: Double) {
        start = now
        phase = withProgress(kind, 0)
    }

    private func duration(of kind: Kind) -> Double {
        switch kind {
        case .borderIn: return Self.dBorderIn
        case .consolidating: return Self.dConsolidate
        case .splashing: return Self.dSplash
        case .igniting: return Self.dIgnite
        case .dismissing: return Self.dDismiss
        case .hidden, .border, .blob: return 0
        }
    }

    private func withProgress(_ kind: Kind, _ p: Double) -> Phase {
        switch kind {
        case .hidden: return .hidden
        case .borderIn: return .borderIn(p)
        case .border: return .border
        case .consolidating: return .consolidating(p)
        case .blob: return .blob
        case .splashing: return .splashing(p)
        case .igniting: return .igniting(p)
        case .dismissing: return .dismissing(p)
        }
    }

    // MARK: - Render params derived from the current phase

    /// Master opacity for the screen border (0 when no border showing).
    var borderIntensity: Double {
        switch phase {
        case .borderIn(let p): return p
        case .border: return 1
        case .consolidating(let p): return 1 - p     // drains as the blob pools
        case .splashing: return 0                     // rim dark until impact
        case .igniting(let p): return p
        case .dismissing(let p): return phaseWasBorder ? 1 - p : 0
        case .hidden, .blob: return 0
        }
    }

    /// Splash-ignition gate for `ScreenBorderView.sweepPhase`. nil = full ring.
    var borderSweep: Double? {
        if case .igniting(let p) = phase { return p }
        return nil
    }

    /// Whether the blob should be drawn at all in the current phase.
    var showsBlob: Bool {
        switch phase.kind {
        case .blob, .consolidating, .splashing: return true
        default: return false
        }
    }

    /// Blob scale envelope: pops to 1.12 as it pools, squashes as it falls.
    var blobScale: Double {
        switch phase {
        case .consolidating(let p):
            // 0 → 1.12 → 1.0 overshoot
            let s = p < 0.7 ? (p / 0.7) * 1.12 : 1.12 - ((p - 0.7) / 0.3) * 0.12
            return s
        case .blob: return 1
        case .splashing: return 1
        default: return 1
        }
    }

    /// Extra wobble amplitude (liquid look) layered onto the blob during pooling.
    var blobAmpBoost: Double {
        if case .consolidating(let p) = phase { return 0.18 * (1 - p) }
        return 0
    }

    /// 0…1 fall progress while splashing (blob travels to the bottom edge).
    var blobFall: Double {
        if case .splashing(let p) = phase { return p }
        return 0
    }

    // Track whether the dismiss began from a border (for fade direction).
    private var phaseWasBorder = false
}
