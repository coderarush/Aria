import Foundation

/// Reads visible text from the current screen using Vision OCR.
struct ScreenOCRTool: AriaTool {
    static let name = "screen_read"
    static let description = "Read visible text from the current screen using OCR. Input: {maxChars} (optional, default 1000)."
    static let paramHints: [String: String] = [
        "maxChars": "Maximum characters to return (default 1000)"
    ]

    private let ocr: ScreenOCR

    init(ocr: ScreenOCR = ScreenOCR.live) {
        self.ocr = ocr
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let maxChars = input["maxChars"].flatMap { Int($0) } ?? 1000
        do {
            let text = try await ocr.readAndTruncate(maxChars: maxChars)
            if text.isEmpty {
                return .ok("Screen text: (no text detected)")
            }
            return .ok("Screen text:\n\(text)")
        } catch ScreenOCRError.captureFailure {
            return .fail("Couldn't capture the screen. Check Screen Recording permission in System Settings → Privacy & Security.")
        } catch ScreenOCRError.permissionDenied {
            return .fail("Screen Recording permission is required. Enable it in System Settings → Privacy & Security.")
        } catch {
            return .fail("Screen text recognition failed: \(error.localizedDescription)")
        }
    }
}
