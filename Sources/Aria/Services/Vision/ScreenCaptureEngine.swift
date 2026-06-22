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

    /// Capture only a sub-region of the primary display and return it as JPEG.
    /// `topLeftRect` is in the display's point space with a TOP-LEFT origin (the
    /// coordinate space SwiftUI/Lens draws in) — the Lens hands us the bounding
    /// box of what the user circled so the model sees *only* that, not the whole
    /// desktop. Clamped to the display; an empty intersection falls back to the
    /// full-frame capture so the caller always gets something usable.
    func captureRegionJPEG(topLeftRect: CGRect) async throws -> Data {
        let full = try await capturePrimaryCGImage()
        let imgRect = CGRect(x: 0, y: 0, width: full.width, height: full.height)
        // Map point-space (top-left) → pixel-space using the captured image's scale.
        let display = try await primaryDisplaySize()
        let scaleX = display.width > 0 ? CGFloat(full.width) / display.width : 1
        let scaleY = display.height > 0 ? CGFloat(full.height) / display.height : 1
        let pxRect = CGRect(x: topLeftRect.minX * scaleX, y: topLeftRect.minY * scaleY,
                            width: topLeftRect.width * scaleX, height: topLeftRect.height * scaleY)
            .integral
            .intersection(imgRect)
        guard !pxRect.isNull, pxRect.width >= 8, pxRect.height >= 8,
              let cropped = full.cropping(to: pxRect) else {
            return try compress(full)
        }
        return try compress(cropped)
    }

    /// The primary display's size in points (for region → pixel mapping).
    private func primaryDisplaySize() async throws -> CGSize {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let d = content.displays.first else { throw CaptureError.noDisplay }
        return CGSize(width: CGFloat(d.width), height: CGFloat(d.height))
    }

    private func capturePrimaryCGImage() async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }
        guard let display = content.displays.first else { throw CaptureError.noDisplay }
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.scalesToFit = true
        config.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw CaptureError.captureFailed
        }
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
