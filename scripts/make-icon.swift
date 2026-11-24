// Draws the app icon (1024x1024 PNG). Run via scripts/make-icon.sh, which also builds the .icns.
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824pt rounded square centred in 1024, soft drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill(); squircle.fill()
ctx.restoreGState()

// Background gradient: deep indigo to bright blue.
ctx.saveGState()
squircle.addClip()
let grad = NSGradient(colors: [NSColor(red: 0.36, green: 0.30, blue: 0.95, alpha: 1),
                               NSColor(red: 0.10, green: 0.62, blue: 0.98, alpha: 1)])!
grad.draw(in: body, angle: -55)
// Soft top highlight.
let gloss = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
gloss.draw(in: CGRect(x: 100, y: 520, width: 824, height: 404), angle: -90)
ctx.restoreGState()

// Viewfinder corner brackets.
NSColor.white.setStroke()
let arm: CGFloat = 110
let l: CGFloat = 250, r: CGFloat = 774, b: CGFloat = 250, t: CGFloat = 774
for (cx, cy, dx, dy) in [(l, t, 1.0, -1.0), (r, t, -1.0, -1.0), (l, b, 1.0, 1.0), (r, b, -1.0, 1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    let p = NSBezierPath()
    p.lineWidth = 46; p.lineCapStyle = .round; p.lineJoinStyle = .round
    p.move(to: CGPoint(x: cx + dx * arm, y: cy))
    p.line(to: CGPoint(x: cx, y: cy))
    p.line(to: CGPoint(x: cx, y: cy + dy * arm))
    p.stroke()
}

// The "name tag": a white pill with a text cursor line and a short second line, as if a filename.
let pill = CGRect(x: 300, y: 417, width: 424, height: 190)
let pillPath = NSBezierPath(roundedRect: pill, xRadius: 52, yRadius: 52)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: NSColor.black.withAlphaComponent(0.28).cgColor)
NSColor.white.setFill(); pillPath.fill()
ctx.restoreGState()
let ink = NSColor(red: 0.20, green: 0.22, blue: 0.62, alpha: 1)
ink.setFill()
NSBezierPath(roundedRect: CGRect(x: 350, y: 527, width: 300, height: 34), xRadius: 17, yRadius: 17).fill()
ink.withAlphaComponent(0.4).setFill()
NSBezierPath(roundedRect: CGRect(x: 350, y: 462, width: 190, height: 34), xRadius: 17, yRadius: 17).fill()
// caret
NSColor(red: 0.10, green: 0.62, blue: 0.98, alpha: 1).setFill()
NSBezierPath(roundedRect: CGRect(x: 668, y: 517, width: 14, height: 56), xRadius: 7, yRadius: 7).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
