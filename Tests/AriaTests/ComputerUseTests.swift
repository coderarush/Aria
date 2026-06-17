import XCTest
@testable import Aria

final class ComputerUseTests: XCTestCase {
    func testCanTypeIntoEditableRolesOnly() {
        XCTAssertTrue(AXReader.canTypeInto(focusedRole: "AXTextField"))
        XCTAssertTrue(AXReader.canTypeInto(focusedRole: "TextArea"))
        XCTAssertTrue(AXReader.canTypeInto(focusedRole: "AXComboBox"))
        XCTAssertFalse(AXReader.canTypeInto(focusedRole: "AXButton"))   // not a text field
        XCTAssertFalse(AXReader.canTypeInto(focusedRole: ""))           // nothing focused
        XCTAssertFalse(AXReader.canTypeInto(focusedRole: "AXStaticText"))
        XCTAssertTrue(AXReader.canTypeInto(focusedRole: "AXWebArea"))   // unknown → permissive
    }

    func testActionableRoles() {
        XCTAssertTrue(AXReader.isActionable(role: "AXButton"))
        XCTAssertTrue(AXReader.isActionable(role: "AXTextField"))
        XCTAssertFalse(AXReader.isActionable(role: "AXStaticText"))
        XCTAssertFalse(AXReader.isActionable(role: "AXGroup"))
    }

    func testBestLabelPrefersTitleThenDescription() {
        XCTAssertEqual(AXReader.bestLabel(title: "Export", description: "d", roleDescription: "r", value: "v"), "Export")
        XCTAssertEqual(AXReader.bestLabel(title: "", description: "Save file", roleDescription: "button", value: ""), "Save file")
        XCTAssertEqual(AXReader.bestLabel(title: " ", description: "", roleDescription: "button", value: "typed"), "typed")
        XCTAssertEqual(AXReader.bestLabel(title: "", description: "", roleDescription: "", value: ""), "")
    }

    func testSummarizeNumbersElements() {
        let els = [
            UIElement(role: "AXButton", label: "Export", value: "", frame: .zero),
            UIElement(role: "AXTextField", label: "Search", value: "cats", frame: .zero)
        ]
        let s = AXReader.summarize(els)
        XCTAssertTrue(s.contains("1. [Button] Export"))
        XCTAssertTrue(s.contains("2. [TextField] Search"))
        XCTAssertTrue(s.contains("cats"))
    }

    func testMenuPathParsing() {
        XCTAssertEqual(UIActuator.menuPath("Format > Font > Bold"), ["Format", "Font", "Bold"])
        XCTAssertEqual(UIActuator.menuPath("  File >  Export  "), ["File", "Export"])
        XCTAssertEqual(UIActuator.menuPath("Bold"), ["Bold"])          // single leaf
        XCTAssertEqual(UIActuator.menuPath("View → Zoom → In"), ["View", "Zoom", "In"])  // arrow too
        XCTAssertEqual(UIActuator.menuPath("  >  "), [])               // empty segments dropped
        XCTAssertEqual(UIActuator.menuPath(""), [])
    }

    func testMenuTitleMatchAllowsEllipsis() {
        // Menu items often carry a trailing ellipsis ("Export…"); a plain query should still match.
        XCTAssertTrue(UIActuator.menuTitleMatches(itemTitle: "Export…", query: "Export"))
        XCTAssertTrue(UIActuator.menuTitleMatches(itemTitle: "Bold", query: "bold"))   // case-insensitive
        XCTAssertFalse(UIActuator.menuTitleMatches(itemTitle: "Italic", query: "Bold"))
        XCTAssertFalse(UIActuator.menuTitleMatches(itemTitle: "", query: "Bold"))
    }

    func testKeyCombosResolve() {
        XCTAssertNotNil(UIActuator.keyCodes["s"])
        XCTAssertEqual(UIActuator.keyCodes["enter"], UIActuator.keyCodes["return"])
        XCTAssertNotNil(UIActuator.keyCodes["escape"])
        XCTAssertNil(UIActuator.keyCodes["f13"])
    }

    func testVisionFractionParsing() {
        XCTAssertEqual(VisionLocator.parseFraction(#"{"x":0.5,"y":0.25}"#), CGPoint(x: 0.5, y: 0.25))
        XCTAssertNil(VisionLocator.parseFraction(#"{"found":false}"#))
        XCTAssertNil(VisionLocator.parseFraction(#"{"x":1.4,"y":0.2}"#))   // out of range
        XCTAssertNil(VisionLocator.parseFraction("no json"))
    }

    func testMatchScoreRanksExactOverContains() {
        XCTAssertEqual(AXReader.matchScore(label: "Export", query: "Export"), 100)        // exact
        XCTAssertGreaterThan(AXReader.matchScore(label: "Export as PNG", query: "Export"), // prefix
                             AXReader.matchScore(label: "Re-export all", query: "export")) // contains
        XCTAssertEqual(AXReader.matchScore(label: "Save", query: "Delete"), 0)            // no match
        XCTAssertEqual(AXReader.matchScore(label: "", query: "x"), 0)
    }

    func testPilotParsesAction() {
        let a = PilotAgent.parse(#"{"tool":"ui_click","input":{"label":"Export"}}"#)
        XCTAssertEqual(a?.tool, "ui_click")
        XCTAssertEqual(a?.input["label"], "Export")
        XCTAssertNil(PilotAgent.parse("not json"))
    }

    // MARK: - Targeting confidence + decision (v11.1.1 operator reliability)

    func testAXConfidenceRisesWithMatchScore() {
        let exact = TargetingConfidence.fromAX(matchScore: 100)
        let weak = TargetingConfidence.fromAX(matchScore: 30)
        XCTAssertEqual(exact.source, .accessibility)
        XCTAssertGreaterThan(exact.value, weak.value)
        XCTAssertLessThanOrEqual(exact.value, 1.0)        // humble — never claims certainty
        XCTAssertGreaterThanOrEqual(weak.value, 0.5)      // a weak contains-match floor
    }

    func testVisionConfidenceUsesReportedScoreOrCautiousDefault() {
        XCTAssertEqual(TargetingConfidence.fromVision(score: 0.9).value, 0.9, accuracy: 1e-9)
        XCTAssertEqual(TargetingConfidence.fromVision(score: nil).value, 0.55, accuracy: 1e-9)
        XCTAssertEqual(TargetingConfidence.fromVision(score: nil).source, .vision)
    }

    func testConfidenceClampsToUnitRange() {
        XCTAssertEqual(TargetingConfidence(source: .vision, value: 1.7).value, 1.0)
        XCTAssertEqual(TargetingConfidence(source: .vision, value: -0.3).value, 0.0)
    }

    func testTargetingDecisionActAskAbort() {
        // At/above threshold → act.
        XCTAssertEqual(OperatorTargeting.decide(confidence: 0.80, threshold: 0.75), .act)
        XCTAssertEqual(OperatorTargeting.decide(confidence: 0.75, threshold: 0.75), .act)
        // Borderline (within the ask band below threshold) → ask first, don't click a guess.
        XCTAssertEqual(OperatorTargeting.decide(confidence: 0.60, threshold: 0.75, askBand: 0.25), .askFirst)
        // Far below → abort.
        XCTAssertEqual(OperatorTargeting.decide(confidence: 0.20, threshold: 0.75, askBand: 0.25), .abort)
    }

    func testTargetingDecisionFromConfidence() {
        // A weak vision guess should not auto-act under the default act threshold.
        let weakVision = TargetingConfidence.fromVision(score: 0.55)
        XCTAssertNotEqual(OperatorTargeting.decide(weakVision), .act)
        // An exact AX hit should act under the default threshold.
        let exactAX = TargetingConfidence.fromAX(matchScore: 100)
        XCTAssertEqual(OperatorTargeting.decide(exactAX), .act)
    }

    // MARK: - Retry policy (re-resolve on retry instead of reusing a stale rect)

    func testRetryFirstAttemptJustAttempts() {
        XCTAssertEqual(RetryPolicy.action(attempt: 0, maxAttempts: 3, lastFailed: false), .attempt)
    }

    func testRetryReresolvesAfterFailure() {
        // Attempt 1 after a failure → re-resolve the element fresh, then retry.
        XCTAssertEqual(RetryPolicy.action(attempt: 1, maxAttempts: 3, lastFailed: true), .reresolveThenRetry)
    }

    func testRetryGivesUpAtBudget() {
        XCTAssertEqual(RetryPolicy.action(attempt: 3, maxAttempts: 3, lastFailed: true), .giveUp)
        XCTAssertEqual(RetryPolicy.action(attempt: 5, maxAttempts: 3, lastFailed: true), .giveUp)
    }

    func testRetryDoesNotReresolveIfPriorAttemptSucceeded() {
        // Defensive: if the loop is re-entered without a failure, just attempt (no waste).
        XCTAssertEqual(RetryPolicy.action(attempt: 1, maxAttempts: 3, lastFailed: false), .attempt)
    }

    // MARK: - Dry-run preview (describe steps without executing)

    func testPreviewDescribesEachStepType() {
        let steps = [
            UIStep(tool: "ui_click", input: ["label": "Send"]),
            UIStep(tool: "ui_type", input: ["text": "Hello there"]),
            UIStep(tool: "ui_key", input: ["combo": "cmd+s"]),
            UIStep(tool: "ui_scroll", input: ["direction": "down"]),
            UIStep(tool: "open_app", input: ["name": "Mail"])
        ]
        let lines = OperatorPreview.preview(steps, app: "Mail")
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines[0], "Click ‘Send’ in Mail")
        XCTAssertEqual(lines[1], "Type ‘Hello there’ in Mail")
        XCTAssertEqual(lines[2], "Press cmd+s in Mail")
        XCTAssertEqual(lines[3], "Scroll down in Mail")
        XCTAssertEqual(lines[4], "Open Mail")
    }

    func testPreviewWithoutAppNameOmitsLocation() {
        let lines = OperatorPreview.preview([UIStep(tool: "ui_click", input: ["label": "OK"])])
        XCTAssertEqual(lines, ["Click ‘OK’"])
    }

    func testPreviewSkipsUnknownAndEmptySteps() {
        let steps = [
            UIStep(tool: "ui_click", input: ["label": ""]),       // empty label → skipped
            UIStep(tool: "frobnicate", input: ["x": "y"]),         // unknown tool → skipped
            UIStep(tool: "ui_click", input: ["label": "Delete"])   // kept
        ]
        XCTAssertEqual(OperatorPreview.preview(steps), ["Click ‘Delete’"])
    }

    func testPreviewTruncatesLongTypedText() {
        let long = String(repeating: "a", count: 200)
        let line = OperatorPreview.line(for: UIStep(tool: "ui_type", input: ["text": long]))
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("…"))   // truncated
        XCTAssertLessThan(line!.count, 80)   // single short line, not a 200-char flood
    }

    func testPreviewIsPureAndDoesNotRequireUI() {
        // The whole point: a preview never touches AX/clicks, so it runs anywhere.
        let lines = OperatorPreview.preview([UIStep(tool: "ui_key", input: ["combo": "enter"])])
        XCTAssertEqual(lines, ["Press enter"])
    }
}
