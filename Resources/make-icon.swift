import AppKit

// Renders the Aria app icon (aurora orb on a dark squircle) at 1024px → icon-1024.png.
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Rounded-square plate, inset a touch (macOS icon grid).
let inset = S * 0.085
let plate = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let corner = (S - inset * 2) * 0.235
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil))
ctx.clip()

// Warm graphite background gradient.
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.13, alpha: 1).cgColor,
                             NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.06, alpha: 1).cgColor] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

// Aurora blobs (radial gradients, screen-blended) — Aria's identity.
func blob(_ cx: CGFloat, _ cy: CGFloat, _ rad: CGFloat, _ c: NSColor) {
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [c.cgColor, c.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: rad, options: [])
    ctx.restoreGState()
}
let mid = S / 2
blob(mid - 150, mid + 150, 430, NSColor(calibratedRed: 0.55, green: 0.36, blue: 1.0, alpha: 0.95))  // violet
blob(mid + 170, mid + 60, 400, NSColor(calibratedRed: 0.20, green: 0.78, blue: 1.0, alpha: 0.9))    // cyan
blob(mid + 40, mid - 180, 380, NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.69, alpha: 0.9))    // pink

// Bright core orb.
let core = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor(white: 1, alpha: 0.95).cgColor,
                               NSColor(calibratedRed: 0.8, green: 0.7, blue: 1, alpha: 0.5).cgColor,
                               NSColor.clear.cgColor] as CFArray, locations: [0, 0.35, 1])!
ctx.setBlendMode(.screen)
ctx.drawRadialGradient(core, startCenter: CGPoint(x: mid, y: mid), startRadius: 0,
                       endCenter: CGPoint(x: mid, y: mid), endRadius: 250, options: [])
ctx.restoreGState()

// Subtle top sheen on the plate edge.
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil))
ctx.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
ctx.setLineWidth(2)
ctx.strokePath()
ctx.restoreGState()

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "Resources/icon-1024.png"))
print("wrote Resources/icon-1024.png")
