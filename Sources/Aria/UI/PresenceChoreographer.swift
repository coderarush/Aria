import SwiftUI

/// Drives the timed transitions between Aria's presence modes:
///
///   hidden → (borderIn) → border
///   border → (consolidating) → blob          // water pooling into a droplet
///   blob   → (splashing → igniting) → border // droplet falls, rim ignites
///   *      → (dismissing) → hidden
///
/// SMOOTHNESS CONTRACT: only the discrete phase `kind` is `@Published` — it
/// changes a handful of times per interaction (at phase boundaries), so SwiftUI
/// invalidates rarely. The continuous 0…1 `progress` and every render parameter
/// are computed PURELY from the TimelineView clock (`at:`), never stored and
/// never published. That removes the per-frame state write that made the motion
/// stutter; the only per-frame work is the TimelineView redraw itself.
@MainActor
final class PresenceChoreographer: ObservableObject {

    enum Kind { case hidden, borderIn, border, consolidating, blob, splashing, igniting, dismissing }

    @Published private(set) var kind: Kind = .hidden

    static let dBorderIn = 0.6
    static let dConsolidate = 1.1
    static let dSplash = 0.45
    static let dIgnite = 0.65
    static let dDismiss = 0.45

    private var target: PresenceMode = .hidden
    private var start: Double = 0          // timestamp the current phase began
    private var phaseWasBorder = false

    // MARK: - Driving (called once per frame from the TimelineView)

    /// React to a new desired mode. No-op while a transition toward the same
    /// target is already in flight. Publishes `kind` only on an actual change.
    func setMode(_ mode: PresenceMode, now: Double) {
        guard mode != target else { return }
        if mode == .hidden {
            phaseWasBorder = [.border, .borderIn, .igniting].contains(kind)
        }
        target = mode
        reconcile(now: now)
    }

    /// Settle the current timed phase if its duration has elapsed (and chain into
    /// the next). Does nothing — and publishes nothing — mid-phase.
    func advance(now: Double) {
        let dur = duration(of: kind)
        guard dur > 0 else { reconcile(now: now); return }
        if now - start >= dur - 1e-9 { settle(now: now) }
    }

    /// 0…1 progress of the current phase at `now` (settled phases report 0).
    func progress(at now: Double) -> Double {
        let dur = duration(of: kind)
        guard dur > 0 else { return 0 }
        return min(1, max(0, (now - start) / dur))
    }

    // MARK: - Transition logic

    private func reconcile(now: Double) {
        switch kind {
        case .borderIn, .consolidating, .splashing, .igniting, .dismissing:
            return  // a transition owns the timeline until it settles
        case .hidden:
            switch target {
            case .hidden: break
            case .border: begin(.borderIn, now)
            case .blob:   begin(.blob, now)        // pop in directly (suggestion / instant blob)
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

    private func settle(now: Double) {
        switch kind {
        case .borderIn:      begin(.border, now);   reconcile(now: now)
        case .consolidating: begin(.blob, now);     reconcile(now: now)
        case .splashing:     begin(.igniting, now)            // splash always chains into ignite
        case .igniting:      begin(.border, now);   reconcile(now: now)
        case .dismissing:    begin(.hidden, now);   reconcile(now: now)
        case .hidden, .border, .blob: break
        }
    }

    private func begin(_ k: Kind, _ now: Double) {
        start = now
        if kind != k { kind = k }      // publish only on real change
    }

    private func duration(of k: Kind) -> Double {
        switch k {
        case .borderIn: return Self.dBorderIn
        case .consolidating: return Self.dConsolidate
        case .splashing: return Self.dSplash
        case .igniting: return Self.dIgnite
        case .dismissing: return Self.dDismiss
        case .hidden, .border, .blob: return 0
        }
    }

    // MARK: - Render parameters (pure functions of the clock)

    /// Smoothstep so every fade eases in/out (silky, no linear ramp).
    private func ease(_ p: Double) -> Double { p * p * (3 - 2 * p) }

    /// Master opacity for the screen border (0 when no border showing).
    func borderIntensity(at now: Double) -> Double {
        let p = progress(at: now)
        switch kind {
        case .borderIn:      return ease(p)
        case .border:        return 1
        case .consolidating: return 1 - ease(p)              // drains as the blob pools
        case .splashing:     return 0                         // rim dark until impact
        case .igniting:      return ease(p)
        case .dismissing:    return phaseWasBorder ? 1 - ease(p) : 0
        case .hidden, .blob: return 0
        }
    }

    /// Splash-ignition gate for `ScreenBorderView.sweepPhase`. nil = full ring.
    func borderSweep(at now: Double) -> Double? {
        kind == .igniting ? progress(at: now) : nil
    }

    /// Progress of the edge-gather (border collapsing into the blob); nil unless
    /// currently consolidating. Drives `EdgeGatherView`.
    func consolidateProgress(at now: Double) -> Double? {
        kind == .consolidating ? progress(at: now) : nil
    }

    /// Whether the blob should be drawn at all in the current phase.
    var showsBlob: Bool {
        switch kind {
        case .blob, .consolidating, .splashing: return true
        default: return false
        }
    }

    /// Blob scale envelope: forms late while pooling, holds at 1 otherwise.
    func blobScale(at now: Double) -> Double {
        guard kind == .consolidating else { return 1 }
        // Stay tiny early, then form from the arriving light with a late overshoot.
        let e = progress(at: now) * progress(at: now)
        return e < 0.8 ? (e / 0.8) * 1.12 : 1.12 - ((e - 0.8) / 0.2) * 0.12
    }

    /// Extra wobble amplitude (liquid look) layered onto the blob while pooling.
    func blobAmpBoost(at now: Double) -> Double {
        kind == .consolidating ? 0.18 * (1 - progress(at: now)) : 0
    }

    /// 0…1 fall progress while splashing (blob travels to the bottom edge).
    func blobFall(at now: Double) -> Double {
        kind == .splashing ? progress(at: now) : 0
    }
}
