import Foundation
import Vision
import AppKit
import CoreGraphics
import ImageIO

/// Errors from ScreenOCR.
enum ScreenOCRError: Error, Equatable {
    case captureFailure
    case recognitionFailure
    case permissionDenied
}

/// Reads text from the current screen via Vision OCR. Fully injectable for
/// testing: `captureScreen` and `recognizeText` are both swappable closures.
struct ScreenOCR: Sendable {

    /// Returns a CGImage of the current screen, or nil on failure.
    var captureScreen: @Sendable () -> CGImage?

    /// Runs text recognition on a CGImage and returns the concatenated text.
    var recognizeText: @Sendable (CGImage) async throws -> String

    // MARK: - Live implementation

    static let live: ScreenOCR = ScreenOCR(
        captureScreen: {
            CGWindowListCreateImage(
                .infinite,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.boundsIgnoreFraming]
            )
        },
        recognizeText: { image in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                throw ScreenOCRError.recognitionFailure
            }
            let results = request.results ?? []
            return results
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }
    )

    // MARK: - API

    /// Capture the screen and return all recognized text.
    func read() async throws -> String {
        guard let image = captureScreen() else {
            throw ScreenOCRError.captureFailure
        }
        do {
            return try await recognizeText(image)
        } catch let err as ScreenOCRError {
            throw err
        } catch {
            throw ScreenOCRError.recognitionFailure
        }
    }

    /// Capture the screen and return recognized text truncated to `maxChars`.
    func readAndTruncate(maxChars: Int = 1000) async throws -> String {
        let result = try await read()
        return String(result.prefix(maxChars))
    }

    /// OCR an arbitrary JPEG region (e.g. a Lens crop) fully on-device. Returns
    /// nil on decode/recognition failure. This is what lets "circle to explain"
    /// work locally with no vision model: most circled things are text/UI, and
    /// the recognized text can be explained by the (local-first) text model.
    static func text(inJPEG data: Data) async -> String? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return try? await live.recognizeText(img)
    }
}
