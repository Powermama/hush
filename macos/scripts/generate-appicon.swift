import AppKit
import CoreGraphics

// Hush app icon generator — the landing-page logo mark rendered to Apple's macOS
// icon grid. Ink squircle (superellipse), white 4-bar waveform (the "hush" glyph),
// peach dot (the "hush•" period). Vector-drawn at each native size, no downscaling.
//
// Palette (from webapp/apps/web/src/styles.css):
//   ink #1F201E · canvas white bars · peach #F78D6B

// ─── Colours ──────────────────────────────────────────────────────────────────
func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}
let inkTop    = rgb(0x2A, 0x29, 0x26)   // subtle top lift for depth
let inkBottom = rgb(0x1A, 0x19, 0x17)   // deep ink base
let barWhite  = rgb(0xF8, 0xF8, 0xF6)   // canvas white
let peach     = rgb(0xF7, 0x8D, 0x6B)

// ─── Squircle (superellipse) path ───────────────────────────────────────────────
func squircle(center c: CGPoint, radius a: CGFloat, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = a * copysign(pow(abs(ct), 2/n), ct)
        let y = a * copysign(pow(abs(st), 2/n), st)
        let pt = CGPoint(x: c.x + x, y: c.y + y)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

// ─── Draw the icon into ctx at the given pixel size ─────────────────────────────
func drawIcon(_ ctx: CGContext, _ size: CGFloat) {
    let s = size / 1024.0            // scale factor from the 1024 design canvas
    func S(_ v: CGFloat) -> CGFloat { v * s }

    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Body: 824×824 squircle centred in the 1024 canvas.
    let center = CGPoint(x: size/2, y: size/2)
    let bodyRadius = S(412)
    let body = squircle(center: center, radius: bodyRadius)

    // Ink vertical gradient fill.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let sp = CGColorSpace(name: CGColorSpace.sRGB)!
    let grad = CGGradient(colorsSpace: sp, colors: [inkTop, inkBottom] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: center.x, y: center.y + bodyRadius),
                           end:   CGPoint(x: center.x, y: center.y - bodyRadius),
                           options: [])
    ctx.restoreGState()

    // Soft top inner highlight — a thin bright edge for a modern "glass" lift.
    ctx.saveGState()
    ctx.addPath(squircle(center: CGPoint(x: center.x, y: center.y - S(1.5)),
                         radius: bodyRadius))
    ctx.addPath(body)
    ctx.clip(using: .evenOdd)
    ctx.addPath(body)
    ctx.setStrokeColor(rgb(0xFF, 0xFF, 0xFF, 0.06))
    ctx.setLineWidth(S(6))
    ctx.strokePath()
    ctx.restoreGState()

    // ─── Waveform bars — the landing logo glyph ────────────────────────────────
    // Logo path heights (viewBox 24): bars at centre y=12 with full heights
    // [4, 12, 7, 3] → normalised. Rendered fully-rounded, ink-white, centred.
    let barW = S(74)
    let gap  = S(66)
    let heightsN: [CGFloat] = [0.34, 1.0, 0.60, 0.24]   // short · tall · mid · short
    let maxH = S(452)
    let count = heightsN.count
    let groupW = CGFloat(count) * barW + CGFloat(count - 1) * gap
    // Just the icon mark — the waveform glyph, centred. (No wordmark, no peach
    // period; the dot belongs to the "hush•" wordmark, not the app icon.)
    let startX = center.x - groupW/2
    let midY   = center.y

    ctx.setFillColor(barWhite)
    for (i, hN) in heightsN.enumerated() {
        let h = maxH * hN
        let x = startX + CGFloat(i) * (barW + gap)
        let rect = CGRect(x: x, y: midY - h/2, width: barW, height: h)
        let bar = CGPath(roundedRect: rect, cornerWidth: barW/2, cornerHeight: barW/2,
                         transform: nil)
        ctx.addPath(bar)
        ctx.fillPath()
    }

}

// ─── Render one PNG at a pixel size ─────────────────────────────────────────────
func renderPNG(size: Int, to path: String) {
    let sp = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0, space: sp,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("ctx")
    }
    drawIcon(ctx, CGFloat(size))
    guard let img = ctx.makeImage() else { fatalError("img") }
    let rep = NSBitmapImageRep(cgImage: img)
    rep.size = NSSize(width: size, height: size)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) @\(size)")
}

// ─── Emit all asset-catalog slots ───────────────────────────────────────────────
let appIcon = CommandLine.arguments[1]   // AppIcon.appiconset dir
let brand   = CommandLine.arguments[2]   // BrandIcon.imageset dir

let slots: [(String, Int)] = [
    ("icon_16.png", 16), ("icon_16@2x.png", 32),
    ("icon_32.png", 32), ("icon_32@2x.png", 64),
    ("icon_128.png", 128), ("icon_128@2x.png", 256),
    ("icon_256.png", 256), ("icon_256@2x.png", 512),
    ("icon_512.png", 512), ("icon_512@2x.png", 1024),
]
for (name, px) in slots { renderPNG(size: px, to: "\(appIcon)/\(name)") }
renderPNG(size: 256, to: "\(brand)/brand-icon.png")
renderPNG(size: 512, to: "\(brand)/brand-icon@2x.png")
print("done")
