import SwiftUI

/// Drives the timed transitions between Aria's presence modes:
///
///   hidden → (blobIn) → blob
///   blob   → (dismissing) → hidden
///
/// Border phases (borderIn, border, consolidating, splashing, igniting) are
/// kept in the enum so nothing else breaks, but PresenceMode no longer
/// requests them — Aria is always the blob when active.
///
/// SMOOTHNESS CONTRACT: only the discrete phase `kind` is `@Published` — it
/// changes a handful of times per interaction (at phase boundaries), so SwiftUI
/// invalidates rarely. The continuous 0…1 `progress` and every render parameter
/// are computed PURELY from the TimelineView clock (`at:`), never stored and
/// never published.
@MainActor
final class PresenceChoreographer: ObservableObject {

    enum Kind { case hidden, borderIn, border, consolidating, blob, splashing, igniting, dismissing, blobIn }

    @Published private(set) var kind: Kind = .hidden

    static let dBorderIn    = 0.6
    static let dConsolidate = 1.1
    static let dSplash      = 0.45
    static let dIgnite      = 0.65
    static let dDismiss     = 0.55
    static let dBlobIn      = 0.38   // quick spring-like entrance

    private var target: PresenceMode = .hidden
    private var start: Double = 0
    private var phaseWasBorder = false

    // MARK: - Driving

    func setMode(_ mode: PresenceMode, now: Double) {
        guard mode != target else { return }
        if mode == .hidden {
            phaseWasBorder = [.border, .borderIn, .igniting].contains(kind)
        }
        target = mode
        reconcile(now: now)
    }

    func advance(now: Double) {
        let dur = duration(of: kind)
        guard dur > 0 else { reconcile(now: now); return }
        if now - start >= dur - 1e-9 { settle(now: now) }
    }

    func progress(at now: Double) -> Double {
        let dur = duration(of: kind)
        guard dur > 0 else { return 0 }
        return min(1, max(0, (now - start) / dur))
    }

    // MARK: - Transition logic

    private func reconcile(now: Double) {
        switch kind {
        case .borderIn, .consolidating, .splashing, .igniting, .dismissing, .blobIn:
            return  // a transition owns the timeline until it settles
        case .hidden:
            switch target {
            case .hidden: break
            case .border: begin(.borderIn, now)
            case .blob:   begin(.blobIn, now)     // spring entrance
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
            case .hidden: begin(.dismissing, now)  // fade out directly
            }
        }
    }

    private func settle(now: Double) {
        switch kind {
        case .blobIn:        begin(.blob, now);     reconcile(now: now)
        case .borderIn:      begin(.border, now);   reconcile(now: now)
        case .consolidating: begin(.blob, now);     reconcile(now: now)
        case .splashing:     begin(.igniting, now)
        case .igniting:      begin(.border, now);   reconcile(now: now)
        case .dismissing:    begin(.hidden, now);   reconcile(now: now)
        case .hidden, .border, .blob: break
        }
    }

    private func begin(_ k: Kind, _ now: Double) {
        start = now
        if kind != k { kind = k }
    }

    private func duration(of k: Kind) -> Double {
        switch k {
        case .blobIn:        return Self.dBlobIn
        case .borderIn:      return Self.dBorderIn
        case .consolidating: return Self.dConsolidate
        case .splashing:     return Self.dSplash
        case .igniting:      return Self.dIgnite
        case .dismissing:    return Self.dDismiss
        case .hidden, .border, .blob: return 0
        }
    }

    // MARK: - Render parameters

    private func ease(_ p: Double) -> Double { p * p * (3 - 2 * p) }

    /// Border glow intensity (unused when PresenceMode never requests .border,
    /// but kept so nothing else breaks).
    func borderIntensity(at now: Double) -> Double {
        let p = progress(at: now)
        switch kind {
        case .borderIn:      return ease(p)
        case .border:        return 1
        case .consolidating: return 1 - ease(p)
        case .splashing:     return 0
        case .igniting:      return ease(p)
        case .dismissing:    return phaseWasBorder ? 1 - ease(p) : 0
        case .hidden, .blob, .blobIn: return 0
        }
    }

    func borderSweep(at now: Double) -> Double? {
        kind == .igniting ? progress(at: now) : nil
    }

    func consolidateProgress(at now: Double) -> Double? {
        kind == .consolidating ? progress(at: now) : nil
    }

    /// Whether the blob should be rendered.
    var showsBlob: Bool {
        switch kind {
        case .blob, .blobIn, .consolidating, .splashing, .dismissing: return true
        default: return false
        }
    }

    /// Blob opacity: fades in on entrance, fades out on dismiss.
    func blobOpacity(at now: Double) -> Double {
        let p = progress(at: now)
        switch kind {
        case .blobIn:      return ease(p)
        case .dismissing:  return 1 - ease(p)
        default:           return 1
        }
    }

    /// Blob scale: overshoots on entrance for a springy pop, normal otherwise.
    func blobScale(at now: Double) -> Double {
        switch kind {
        case .blobIn:
            let p = ease(progress(at: now))
            // Overshoot: scale up to 1.14 then settle to 1.0
            return p < 0.75 ? (p / 0.75) * 1.14 : 1.14 - ((p - 0.75) / 0.25) * 0.14
        case .consolidating:
            let e = progress(at: now) * progress(at: now)
            return e < 0.8 ? (e / 0.8) * 1.12 : 1.12 - ((e - 0.8) / 0.2) * 0.12
        default: return 1
        }
    }

    func blobAmpBoost(at now: Double) -> Double {
        kind == .consolidating ? 0.18 * (1 - progress(at: now)) : 0
    }

    func blobFall(at now: Double) -> Double {
        kind == .splashing ? progress(at: now) : 0
    }
}
