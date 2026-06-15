import XCTest
import CoreGraphics
@testable import Aria

final class ScreenOCRTests: XCTestCase {

    // MARK: - Helpers

    /// Makes a minimal 1×1 CGImage that won't trigger a real OCR path.
    private func make1x1Image() -> CGImage {
        let ctx = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    // MARK: - Tests

    func testReadReturnsRecognizedText() async throws {
        let img = make1x1Image()
        let ocr = ScreenOCR(
            captureScreen: { img },
            recognizeText: { _ in "Hello World" }
        )
        let result = try await ocr.read()
        XCTAssertEqual(result, "Hello World")
    }

    func testReadThrowsOnNilCapture() async throws {
        let ocr = ScreenOCR(
            captureScreen: { nil },
            recognizeText: { _ in "should not reach" }
        )
        do {
            _ = try await ocr.read()
            XCTFail("Expected captureFailure")
        } catch ScreenOCRError.captureFailure {
            // expected
        }
    }

    func testReadAndTruncate() async throws {
        let longText = String(repeating: "A", count: 2000)
        let img = make1x1Image()
        let ocr = ScreenOCR(
            captureScreen: { img },
            recognizeText: { _ in longText }
        )
        let result = try await ocr.readAndTruncate(maxChars: 100)
        XCTAssertEqual(result.count, 100)
    }

    func testReadThrowsOnRecognitionFailure() async throws {
        let img = make1x1Image()
        let ocr = ScreenOCR(
            captureScreen: { img },
            recognizeText: { _ in throw ScreenOCRError.recognitionFailure }
        )
        do {
            _ = try await ocr.read()
            XCTFail("Expected recognitionFailure")
        } catch ScreenOCRError.recognitionFailure {
            // expected
        }
    }

    func testReadAndTruncateWithExactLength() async throws {
        let text = String(repeating: "B", count: 50)
        let img = make1x1Image()
        let ocr = ScreenOCR(
            captureScreen: { img },
            recognizeText: { _ in text }
        )
        let result = try await ocr.readAndTruncate(maxChars: 1000)
        // Under the limit — should return full text.
        XCTAssertEqual(result, text)
    }
}
