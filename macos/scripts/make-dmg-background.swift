#!/usr/bin/env swift
//
// Generates the brand-tinted DMG installer background:
//   scripts/dmg-background.png  (540 × 380, used by release-dmg.sh)
//
// The image is a soft cream wash matching `DesignTokens.paper` from the
// app, with a curved arrow in brand-orange pointing from where the
// Hush.app icon will sit (140, 180) to where the Applications drop-
// link will sit (400, 180). Those coordinates are mirrored from the
// `--icon`/`--app-drop-link` args in `release-dmg.sh` — keep them in
// sync if you ever resize the DMG window.
//
// Run:    swift scripts/make-dmg-background.swift
// Output: scripts/dmg-background.png
//
// Why a Swift script instead of a hand-designed PNG: this lives next to
// the create-dmg call that uses it, so a future tweak (window size,
// icon position, brand colour) is one number change here — no Figma
// roundtrip, no binary asset drift.

import AppKit
import CoreGraphics

// ---------------------------------------------------------------------
// Geometry — must match the icon positions in release-dmg.sh.
// ---------------------------------------------------------------------

let windowWidth:  CGFloat = 540
let windowHeight: CGFloat = 380
let iconY:        CGFloat = 180   // both icons sit at the same Y in the DMG window
let hushIconX:  CGFloat = 140
let appsIconX:    CGFloat = 400
let iconHalfSize: CGFloat = 55    // icon-size 110 / 2

// CoreGraphics origin is bottom-left; create-dmg/Finder use top-left.
// Convert by flipping Y: pngY = windowHeight - dmgY.
let arrowY = windowHeight - iconY

// Render at 2× for Retina. Finder draws the DMG background as a Tiff/
// PNG and respects @2x bitmap density via embedded DPI — without this
// the text label looks fuzzy on every Retina Mac (any Mac since 2016).
// Drawing into a 1080×760 context and saving as a single high-DPI PNG
// gives crisp text without touching the create-dmg coordinate space
// (which is still in 1× points for icon positions).
let scale: CGFloat = 2
let pixelWidth  = Int(windowWidth  * scale)
let pixelHeight = Int(windowHeight * scale)

// ---------------------------------------------------------------------
// Colours — match the app's DesignTokens (Hush/Design/DesignTokens.swift)
// and the landing page: warm off-white, ink, peach + lilac.
// ---------------------------------------------------------------------

let canvas = NSColor(srgbRed: 0xF8/255, green: 0xF8/255, blue: 0xF6/255, alpha: 1)
let stone  = NSColor(srgbRed: 0xF0/255, green: 0xF0/255, blue: 0xED/255, alpha: 1)
let peach  = NSColor(srgbRed: 0xF7/255, green: 0x8D/255, blue: 0x6B/255, alpha: 1)
let lilac  = NSColor(srgbRed: 0xDD/255, green: 0xD8/255, blue: 0xFF/255, alpha: 1)
let inkDim = NSColor(srgbRed: 0x68/255, green: 0x69/255, blue: 0x63/255, alpha: 1)
let arrowColor = peach

// ---------------------------------------------------------------------
// Draw
// ---------------------------------------------------------------------

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: pixelWidth,
    height: pixelHeight,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("✗ Could not create bitmap context\n".data(using: .utf8)!)
    exit(1)
}
// Scale up so every draw call below can use 1× point coordinates and
// produce 2× pixel-perfect output without us threading `scale` through
// every CGRect.
ctx.scaleBy(x: scale, y: scale)

// Background — warm off-white gradient (canvas → stone), matching the app's
// paper surfaces and the landing page.
let sp = CGColorSpace(name: CGColorSpace.sRGB)!
if let bg = CGGradient(colorsSpace: sp,
                       colors: [canvas.cgColor, stone.cgColor] as CFArray,
                       locations: [0, 1]) {
    ctx.drawLinearGradient(bg,
                           start: CGPoint(x: 0, y: windowHeight),
                           end: CGPoint(x: 0, y: 0), options: [])
}

// Soft lilac-over-peach glow up top — the landing page's hero wash.
func glow(_ color: NSColor, at center: CGPoint, radius: CGFloat, alpha: CGFloat) {
    guard let g = CGGradient(colorsSpace: sp,
                             colors: [color.withAlphaComponent(alpha).cgColor,
                                      color.withAlphaComponent(0).cgColor] as CFArray,
                             locations: [0, 1]) else { return }
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius, options: [])
}
glow(lilac, at: CGPoint(x: windowWidth/2, y: 300), radius: 230, alpha: 0.50)
glow(peach, at: CGPoint(x: windowWidth/2 - 60, y: 250), radius: 200, alpha: 0.16)

// Arrow geometry. Starts past the right edge of the Hush icon, ends
// just before the left edge of the Applications folder. Small gap on
// each side so the line doesn't visually touch the icons.
let gap: CGFloat = 22
let lineStart = CGPoint(x: hushIconX + iconHalfSize + gap, y: arrowY)
let lineEnd   = CGPoint(x: appsIconX   - iconHalfSize - gap, y: arrowY)

// Shaft — thick rounded stroke. Width chosen to read clearly without
// dominating the 110pt icons.
ctx.setStrokeColor(arrowColor.cgColor)
ctx.setLineWidth(5)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let shaft = CGMutablePath()
shaft.move(to: lineStart)
shaft.addLine(to: CGPoint(x: lineEnd.x - 10, y: lineEnd.y))
ctx.addPath(shaft)
ctx.strokePath()

// Arrowhead — solid filled triangle so it stays crisp at 1×/2×/3×.
let arrowheadLength: CGFloat = 18
let arrowheadHalfWidth: CGFloat = 11
let tip   = lineEnd
let back1 = CGPoint(x: tip.x - arrowheadLength, y: tip.y - arrowheadHalfWidth)
let back2 = CGPoint(x: tip.x - arrowheadLength, y: tip.y + arrowheadHalfWidth)

ctx.setFillColor(arrowColor.cgColor)
let head = CGMutablePath()
head.move(to: tip)
head.addLine(to: back1)
head.addLine(to: back2)
head.closeSubpath()
ctx.addPath(head)
ctx.fillPath()

// "drag to install" hint above the arrow. SF Pro is the canonical macOS
// system font — preferred over Helvetica Neue because the install
// screen reads as part of macOS itself. Falls back through the system
// font if SF Pro is unavailable (very rare; ships with every macOS
// since 10.11). 13pt semibold is the sweet spot for legibility at the
// distance users typically view DMG windows from.
let font = NSFont.systemFont(ofSize: 13, weight: .medium)
let textColor = inkDim
let label = NSAttributedString(
    string: "drag to install",
    attributes: [
        .font: font,
        .foregroundColor: textColor,
        .kern: 0.3
    ]
)
let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsCtx
let textSize = label.size()
let textX = (lineStart.x + lineEnd.x) / 2 - textSize.width / 2
let textY = arrowY + 18
label.draw(at: CGPoint(x: textX, y: textY))
NSGraphicsContext.restoreGraphicsState()

// ---------------------------------------------------------------------
// Encode + save
// ---------------------------------------------------------------------

guard let cgImage = ctx.makeImage() else {
    FileHandle.standardError.write("✗ Could not make CGImage\n".data(using: .utf8)!)
    exit(1)
}
// Build a bitmap rep that knows its *point* size is windowWidth ×
// windowHeight (not pixelWidth × pixelHeight). This is what makes the
// PNG a "Retina" asset — Finder reads the @2× DPI and draws it at the
// logical 540 × 380 backing size, keeping pixels crisp.
let rep = NSBitmapImageRep(cgImage: cgImage)
rep.size = NSSize(width: windowWidth, height: windowHeight)
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("✗ Could not encode PNG\n".data(using: .utf8)!)
    exit(1)
}

// Resolve output path relative to the script itself, so running it from
// anywhere produces the file at `scripts/dmg-background.png`.
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let outputURL = scriptURL.deletingLastPathComponent()
    .appendingPathComponent("dmg-background.png")
try png.write(to: outputURL)

print("✓ Wrote \(outputURL.path) (\(png.count) bytes)")
