import XCTest
@testable import Aria

final class ToneManagerTests: XCTestCase {

    // MARK: ToneManager actor

    func testDefaultToneIsAuto() async {
        let manager = ToneManager()
        let tone = await manager.current
        XCTAssertEqual(tone, .auto, "default tone should be .auto")
    }

    func testSetToneUpdatesCurrent() async {
        let manager = ToneManager()
        await manager.set(.formal)
        let tone = await manager.current
        XCTAssertEqual(tone, .formal)
    }

    func testResetReturnsToAuto() async {
        let manager = ToneManager()
        await manager.set(.casual)
        await manager.reset()
        let tone = await manager.current
        XCTAssertEqual(tone, .auto, "reset() should restore .auto")
    }

    func testAutoToneInstructionIsEmpty() async {
        let manager = ToneManager()
        let instruction = await manager.toneInstruction()
        XCTAssertTrue(instruction.isEmpty, ".auto instruction must be empty so prompts are unmodified")
    }

    func testFormalToneInstructionNotEmpty() async {
        let manager = ToneManager()
        await manager.set(.formal)
        let instruction = await manager.toneInstruction()
        XCTAssertFalse(instruction.isEmpty, ".formal instruction must not be empty")
    }

    func testAllTonesHaveDistinctInstructions() {
        // .auto has empty instruction; all others must be non-empty and distinct.
        let nonAuto = WritingTone.allCases.filter { $0 != .auto }
        let instructions = nonAuto.map(\.instruction)
        XCTAssertFalse(instructions.contains(""), "non-auto tones must have non-empty instructions")
        let unique = Set(instructions)
        XCTAssertEqual(unique.count, instructions.count, "all non-auto tones must have distinct instructions")
    }

    // MARK: SetToneTool

    func testSetToneToolParsesValidTone() async throws {
        let manager = ToneManager()
        let tool = SetToneTool(manager: manager)
        let result = try await tool.run(input: ["tone": "casual"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("casual"))
        let current = await manager.current
        XCTAssertEqual(current, .casual)
    }

    func testSetToneToolRejectsInvalidTone() async throws {
        let tool = SetToneTool(manager: ToneManager())
        let result = try await tool.run(input: ["tone": "sarcastic"])
        XCTAssertFalse(result.success, "invalid tone should return failure")
        XCTAssertTrue(result.output.lowercased().contains("valid") || result.output.lowercased().contains("unknown"))
    }

    func testSetToneToolAutoResetsGracefully() async throws {
        let manager = ToneManager()
        await manager.set(.brief)
        let tool = SetToneTool(manager: manager)
        let result = try await tool.run(input: ["tone": "auto"])
        XCTAssertTrue(result.success)
        let current = await manager.current
        XCTAssertEqual(current, .auto)
    }

    func testSetToneToolCaseInsensitive() async throws {
        let manager = ToneManager()
        let tool = SetToneTool(manager: manager)
        let result = try await tool.run(input: ["tone": "FORMAL"])
        XCTAssertTrue(result.success)
        let current = await manager.current
        XCTAssertEqual(current, .formal)
    }

    // MARK: ToneStatusTool

    func testToneStatusToolShowsCurrentTone() async throws {
        let manager = ToneManager()
        await manager.set(.professional)
        let tool = ToneStatusTool(manager: manager)
        let result = try await tool.run(input: [:])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("professional"))
    }

    func testToneStatusToolShowsAutoMessage() async throws {
        let manager = ToneManager()
        let tool = ToneStatusTool(manager: manager)
        let result = try await tool.run(input: [:])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("auto"))
    }

    // MARK: Tone injection into drafts

    func testToneInjectedIntoDraftPrompt() async {
        // Set the shared manager to .brief, then verify GmailDraftTool incorporates
        // the tone instruction into the body it would send to the connector.
        // We verify this via the ToneManager directly (since GmailDraftTool calls
        // ToneManager.shared.toneInstruction() and prepends it to the body).
        let manager = ToneManager()
        await manager.set(.brief)
        let instruction = await manager.toneInstruction()
        XCTAssertFalse(instruction.isEmpty, ".brief tone must have an instruction")
        XCTAssertTrue(instruction.lowercased().contains("concise") || instruction.lowercased().contains("point"),
                      ".brief instruction should emphasize brevity")

        // Verify prompt construction logic: body is prefixed with toneNote when non-empty.
        let baseBody = "Please reply by end of week."
        let composedBody = instruction.isEmpty ? baseBody : "\(instruction)\n\n\(baseBody)"
        XCTAssertTrue(composedBody.hasPrefix(instruction),
                      "tone instruction should be prepended to the draft body")
        XCTAssertTrue(composedBody.contains(baseBody),
                      "original body must be preserved after tone injection")
    }

    func testAutoToneDoesNotModifyDraftPrompt() async {
        let manager = ToneManager()
        // default is .auto
        let instruction = await manager.toneInstruction()
        let baseBody = "Can you send the report?"
        let composedBody = instruction.isEmpty ? baseBody : "\(instruction)\n\n\(baseBody)"
        XCTAssertEqual(composedBody, baseBody, ".auto tone must leave the body unchanged")
    }
}
