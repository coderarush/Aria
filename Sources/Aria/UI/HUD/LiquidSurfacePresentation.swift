import Foundation
import CoreGraphics

enum LiquidSurfacePhase: Equatable {
    case resting, ready, composing, listening, working, answering, error
}

enum LiquidInvocationSource: Equatable {
    case blobClick, keyboard, voice, systemDictation
}

enum LiquidExpansionEdge: CaseIterable, Equatable {
    case left, right, above, below
}

struct LiquidSurfaceLayout: Equatable {
    let anchor: CGPoint
    let expansionEdge: LiquidExpansionEdge
    let panelFrame: CGRect
    let collapsedCenter: CGPoint
    let expandedFrame: CGRect

    static func make(anchor: CGPoint, visibleFrame: CGRect, collapsedDiameter: CGFloat) -> LiquidSurfaceLayout {
        let margin: CGFloat = 20
        let safe = visibleFrame.insetBy(dx: margin, dy: margin)
        let width = min(520, max(1, safe.width))
        let height = min(220, max(1, safe.height))
        let gap: CGFloat = 12
        let half = collapsedDiameter / 2

        func proposed(_ edge: LiquidExpansionEdge) -> CGRect {
            switch edge {
            case .left:  return CGRect(x: anchor.x - half - gap - width, y: anchor.y - height / 2, width: width, height: height)
            case .right: return CGRect(x: anchor.x + half + gap, y: anchor.y - height / 2, width: width, height: height)
            case .above: return CGRect(x: anchor.x - width / 2, y: anchor.y - half - gap - height, width: width, height: height)
            case .below: return CGRect(x: anchor.x - width / 2, y: anchor.y + half + gap, width: width, height: height)
            }
        }
        func overflow(_ rect: CGRect) -> CGFloat {
            max(0, safe.minX - rect.minX) + max(0, rect.maxX - safe.maxX)
                + max(0, safe.minY - rect.minY) + max(0, rect.maxY - safe.maxY)
        }
        let edge = LiquidExpansionEdge.allCases.min { overflow(proposed($0)) < overflow(proposed($1)) } ?? .above
        let frame = proposed(edge)
        let clamped = CGRect(x: min(max(frame.minX, safe.minX), safe.maxX - width),
                             y: min(max(frame.minY, safe.minY), safe.maxY - height),
                             width: width, height: height)
        return LiquidSurfaceLayout(anchor: anchor, expansionEdge: edge, panelFrame: clamped,
                                   collapsedCenter: anchor, expandedFrame: clamped)
    }
}

struct LiquidCue: Equatable {
    enum Kind: Equatable { case proactiveSuggestion, resumableTask, setupRequirement, recentCommand }
    let kind: Kind
    let text: String
}

struct LiquidMotionProfile: Equatable {
    let activeFramesPerSecond: Int
    let idleFramesPerSecond: Int
    let deformationAmplitude: CGFloat
    let transitionDuration: TimeInterval

    static let standard = LiquidMotionProfile(activeFramesPerSecond: 60, idleFramesPerSecond: 12,
                                              deformationAmplitude: 0.16, transitionDuration: 0.22)
    static let reducedMotion = LiquidMotionProfile(activeFramesPerSecond: 0, idleFramesPerSecond: 0,
                                                   deformationAmplitude: 0, transitionDuration: 0.12)
}

enum ResponseHeadline {
    static func make(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let sentence = trimmed.split(maxSplits: 1, omittingEmptySubsequences: true,
                                     whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? trimmed
        let suffix = trimmed.dropFirst(sentence.count).first.flatMap { ".!?".contains($0) ? String($0) : nil } ?? ""
        let result = (sentence.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) + suffix)
        return result.count <= 160 ? result : String(result.prefix(157)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) + "..."
    }
}
