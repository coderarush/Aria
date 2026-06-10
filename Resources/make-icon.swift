import AppKit

// Renders the Aria app icon — the black organic blob on warm cream, matching
// the website identity (docs/v9/ariawebsitedesign.png) — at 1024px → icon-1024.png.
// Regenerate AppIcon.icns afterwards (see Makefile `icon` target).

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Rounded-square plate (macOS icon grid), warm cream like the site background.
let inset = S * 0.085
let plate = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let corner = (S - inset * 2) * 0.235
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil))
ctx.clip()

let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [NSColor(calibratedRed: 0.95, green: 0.93, blue: 0.89, alpha: 1).cgColor,   // cream #f1ede2
                             NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.82, alpha: 1).cgColor] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

// The blob — same layered-sine outline as BlobMath / the website canvas.
func blobPath(cx: CGFloat, cy: CGFloat, base: CGFloat, t: CGFloat, amp: CGFloat) -> CGPath {
    let n = 11
    var pts: [CGPoint] = []
    for i in 0..<n {
        let a = CGFloat(i)
        let w = 0.6 * sin(t + a * 0.9) + 0.3 * sin(t * 1.7 + a * 1.7) + 0.1 * sin(t * 0.5 + a * 2.3)
        let r = base * (1 + amp * w)
        let ang = 2 * .pi * a / CGFloat(n) - .pi / 2
        pts.append(CGPoint(x: cx + cos(ang) * r, y: cy + sin(ang) * r))
    }
    let path = CGMutablePath()
    func pt(_ i: Int) -> CGPoint { pts[((i % n) + n) % n] }
    path.move(to: pt(0))
    for i in 0..<n {
        let p0 = pt(i - 1), p1 = pt(i), p2 = pt(i + 1), p3 = pt(i + 2)
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        path.addCurve(to: p2, control1: c1, control2: c2)
    }
    path.closeSubpath()
    return path
}

// Soft drop shadow, then the warm near-black body with a gel highlight.
let body = blobPath(cx: S * 0.5, cy: S * 0.52, base: S * 0.30, t: 0.6, amp: 0.10)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.02), blur: S * 0.05,
              color: NSColor.black.withAlphaComponent(0.30).cgColor)
ctx.addPath(body)
ctx.setFillColor(NSColor(calibratedRed: 0.082, green: 0.075, blue: 0.06, alpha: 1).cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(body)
ctx.clip()
let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [NSColor.white.withAlphaComponent(0.20).cgColor,
                                NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                       locations: [0, 1])!
ctx.drawRadialGradient(sheen,
                       startCenter: CGPoint(x: S * 0.40, y: S * 0.62), startRadius: 8,
                       endCenter: CGPoint(x: S * 0.40, y: S * 0.62), endRadius: S * 0.34,
                       options: [])
ctx.restoreGState()
ctx.restoreGState()

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "Resources/icon-1024.png"))
print("wrote Resources/icon-1024.png")
