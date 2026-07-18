import XCTest
@testable import Aria

final class LiquidSurfacePresentationTests: XCTestCase {
    func testHeadlineUsesFirstUsefulSentenceAndCapsLength() {
        XCTAssertEqual(ResponseHeadline.make(from: "  Hello there. Here is more detail."), "Hello there.")
        XCTAssertEqual(ResponseHeadline.make(from: "\n\n"), "")
        XCTAssertLessThanOrEqual(ResponseHeadline.make(from: String(repeating: "a", count: 220)).count, 160)
    }

    func testLayoutChoosesVisibleExpansionAwayFromBottomRightCorner() {
        let visible = CGRect(x: 0, y: 0, width: 900, height: 700)
        let layout = LiquidSurfaceLayout.make(anchor: CGPoint(x: 850, y: 650),
                                              visibleFrame: visible,
                                              collapsedDiameter: 84)
        XCTAssertEqual(layout.expansionEdge, .left)
        XCTAssertTrue(visible.insetBy(dx: 20, dy: 20).contains(layout.expandedFrame))
    }

    func testLayoutStaysWithinSmallVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 380, height: 280)
        let layout = LiquidSurfaceLayout.make(anchor: CGPoint(x: 190, y: 140),
                                              visibleFrame: visible,
                                              collapsedDiameter: 84)
        XCTAssertTrue(visible.insetBy(dx: 20, dy: 20).contains(layout.expandedFrame))
        XCTAssertGreaterThanOrEqual(layout.expandedFrame.width, 340)
    }
}

@MainActor
final class LiquidSurfaceStateTests: XCTestCase {
    func testTypedDraftAndAnswerBecomeSurfacePresentation() {
        let vm = IslandViewModel()
        vm.beginComposing(source: .keyboard)
        vm.updateDraft("Draft")
        XCTAssertEqual(vm.liquidPhase, .composing)
        XCTAssertEqual(vm.draftText, "Draft")

        vm.showResponse("A clear answer. More context follows.")
        XCTAssertEqual(vm.liquidPhase, .answering)
        XCTAssertEqual(vm.responseHeadline, "A clear answer.")
    }

    func testPartialTranscriptReplacesRatherThanAppends() {
        let vm = IslandViewModel()
        vm.beginListening(source: .voice)
        vm.replacePartialTranscript("open cal")
        vm.replacePartialTranscript("open calendar")
        XCTAssertEqual(vm.draftText, "open calendar")
    }
}
