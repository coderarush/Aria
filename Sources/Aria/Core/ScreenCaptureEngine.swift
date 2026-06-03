import Foundation
import ScreenCaptureKit
import CoreImage
import AppKit

/// Captures the primary display via ScreenCaptureKit on demand (never
/// continuously). Output is JPEG, max 1920px wide, quality 0.75. Screenshots are
/// kept only in memory (last 3) and never written to disk.
actor ScreenCaptureEngine {

    enum CaptureError: Error {
        case noDisplay
        case captureFailed
        case permissionDenied
    }

    private var recent: [Data] = []
    private let maxRecent = 3
    private let maxWidth: CGFloat = 1920
    private let jpegQuality: CGFloat = 0.75
    private let ciContext = CIContext()

    /// Most recent screenshots, newest last. For "what was on my screen a minute ago?".
    func recentScreenshots() -> [Data] { recent }

    /// Capture the primary display and return compressed JPEG bytes.
    func capturePrimaryJPEG() async throws -> Data {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
        } catch {
            Log.screen.error("ScreenCaptureKit content failed: \(error.localizedDescription)")
            throw CaptureError.permissionDenied
        }

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.scalesToFit = true
        config.showsCursor = false

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        } catch {
            Log.screen.error("Capture failed: \(error.localizedDescription)")
            throw CaptureError.captureFailed
        }

        let jpeg = try compress(cgImage)
        store(jpeg)
        return jpeg
    }

    // MARK: Compression

    private func compress(_ cgImage: CGImage) throws -> Data {
        var ciImage = CIImage(cgImage: cgImage)
        let width = CGFloat(cgImage.width)
        if width > maxWidth {
            let scale = maxWidth / width
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let jpeg = ciContext.jpegRepresentation(
                of: ciImage,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: jpegQuality])
        else {
            throw CaptureError.captureFailed
        }
        return jpeg
    }

    private func store(_ jpeg: Data) {
        recent.append(jpeg)
        if recent.count > maxRecent {
            recent.removeFirst(recent.count - maxRecent)
        }
    }
}
