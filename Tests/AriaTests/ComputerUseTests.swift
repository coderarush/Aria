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
}
