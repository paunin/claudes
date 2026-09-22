#!/usr/bin/env swift
// Renders the README banner: one Mac, a row of separately tinted and badged
// Claude apps. Same toolchain as render-icon.swift - AppKit only, no
// third-party dependencies - so the artwork can be regenerated from source:
//
//     swift render-banner.swift docs/banner.png
//
// The labels here are deliberately generic. Real slugs and organisation names
// live in the gitignored instances.conf and must not leak into a tracked image.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/banner.png"
let W = 1600.0, H = 520.0

// label, hue, note
let tiles: [(String, CGFloat)] = [
  ("ME",   0.045),   // personal profile: Claude's own orange, left untinted
  ("ACME", 0.560),
  ("LAB",  0.380),
  ("DEV",  0.720),
  ("OPS",  0.905),
]

guard let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
  let ctx = NSGraphicsContext(bitmapImageRep: rep)
else { FileHandle.standardError.write("cannot create bitmap\n".data(using: .utf8)!); exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

// --- background: warm near-black, lifted slightly behind the row of apps ----
NSGradient(colors: [
  NSColor(calibratedRed: 0.086, green: 0.078, blue: 0.074, alpha: 1),
  NSColor(calibratedRed: 0.137, green: 0.122, blue: 0.113, alpha: 1),
])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)

// A full-width band rather than a shape, so the light has no visible edge.
NSGradient(colors: [
  NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 0.00),
  NSColor(calibratedRed: 0.87, green: 0.52, blue: 0.38, alpha: 0.10),
  NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 0.00),
])!.draw(in: NSRect(x: 0, y: 120, width: W, height: 330), angle: 90)

func text(_ s: String, _ font: NSFont, _ color: NSColor, centeredIn r: NSRect) {
  let p = NSMutableParagraphStyle(); p.alignment = .center
  let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
  let str = NSAttributedString(string: s, attributes: a)
  let h = str.size().height
  str.draw(in: NSRect(x: r.minX, y: r.midY - h/2, width: r.width, height: h))
}

// --- the row of app tiles ---------------------------------------------------
let side = 150.0, gap = 32.0
let rowW = Double(tiles.count) * side + Double(tiles.count - 1) * gap
var x = (W - rowW) / 2
let y = 206.0

for (label, hue) in tiles {
  let rect = NSRect(x: x, y: y, width: side, height: side)
  let path = NSBezierPath(roundedRect: rect, xRadius: 36, yRadius: 36)

  NSGraphicsContext.saveGraphicsState()
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
  shadow.shadowBlurRadius = 26
  shadow.shadowOffset = NSSize(width: 0, height: -10)
  shadow.set()
  NSGradient(colors: [
    NSColor(calibratedHue: hue, saturation: 0.58, brightness: 0.95, alpha: 1),
    NSColor(calibratedHue: hue, saturation: 0.74, brightness: 0.72, alpha: 1),
  ])!.draw(in: path, angle: -90)
  NSGraphicsContext.restoreGraphicsState()

  // top highlight, so the tiles read as glass rather than flat swatches
  NSColor.white.withAlphaComponent(0.20).setStroke()
  let inner = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), xRadius: 34, yRadius: 34)
  inner.lineWidth = 3
  inner.stroke()

  let size = label.count >= 4 ? 40.0 : 52.0
  text(label, .systemFont(ofSize: size, weight: .heavy),
       NSColor.white.withAlphaComponent(0.96),
       centeredIn: NSRect(x: x, y: y, width: side, height: side))

  // reflection, so the row sits on a surface instead of floating
  let refl = NSBezierPath(roundedRect: NSRect(x: x, y: y - 56, width: side, height: 52),
                          xRadius: 30, yRadius: 30)
  NSGradient(colors: [
    NSColor(calibratedHue: hue, saturation: 0.62, brightness: 0.90, alpha: 0.00),
    NSColor(calibratedHue: hue, saturation: 0.62, brightness: 0.90, alpha: 0.16),
  ])!.draw(in: refl, angle: 90)

  x += side + gap
}

// --- wordmark ---------------------------------------------------------------
text("Claudes", .systemFont(ofSize: 92, weight: .bold),
     NSColor(calibratedWhite: 0.98, alpha: 1),
     centeredIn: NSRect(x: 0, y: 396, width: W, height: 100))

text("several Claude accounts on one Mac  ·  a separate desktop app and CLI profile for each",
     .systemFont(ofSize: 29, weight: .regular),
     NSColor(calibratedRed: 0.85, green: 0.78, blue: 0.73, alpha: 0.82),
     centeredIn: NSRect(x: 0, y: 96, width: W, height: 40))

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
