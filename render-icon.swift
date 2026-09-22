// Tint and badge every PNG of a macOS .iconset, in place.
//   usage: swift render-icon.swift <iconset-dir> <LABEL> <hue>
//
// <hue> uses ImageMagick's -modulate convention so instances.conf stays readable:
// 100 leaves the hue unchanged and the 0...200 range maps onto -180...+180 degrees.
// Saturation is boosted 15% to match Claude's own icon punch.
//
// Uses only CoreImage and AppKit, so the repo needs no third-party tools.
// Sizes under 128px are tinted but not badged - the letters would be mush there,
// and the tint alone distinguishes them in menus and list views.
import AppKit
import CoreImage

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write("usage: <iconset-dir> <LABEL> <hue>\n".data(using: .utf8)!)
    exit(2)
}
let dir = args[1], label = args[2]
guard let hue = Double(args[3]) else {
    FileHandle.standardError.write("hue must be a number\n".data(using: .utf8)!); exit(2)
}
let angle = (hue - 100.0) * 1.8 * .pi / 180.0   // modulate units -> radians
let saturation = 1.45   // tuned to match ImageMagick -modulate 100,115,H

let ciContext = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])

func tint(_ cg: CGImage) -> CGImage? {
    var img = CIImage(cgImage: cg)
    if saturation != 1.0 {
        let f = CIFilter(name: "CIColorControls")!
        f.setValue(img, forKey: kCIInputImageKey)
        f.setValue(saturation, forKey: kCIInputSaturationKey)
        img = f.outputImage ?? img
    }
    if angle != 0 {
        let f = CIFilter(name: "CIHueAdjust")!
        f.setValue(img, forKey: kCIInputImageKey)
        f.setValue(angle, forKey: kCIInputAngleKey)
        img = f.outputImage ?? img
    }
    return ciContext.createCGImage(img, from: CIImage(cgImage: cg).extent)
}

let files = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.filter { $0.hasSuffix(".png") } ?? []
guard !files.isEmpty else {
    FileHandle.standardError.write("no PNGs in \(dir)\n".data(using: .utf8)!); exit(3)
}

for name in files.sorted() {
    let path = (dir as NSString).appendingPathComponent(name)
    guard let src = NSImage(contentsOfFile: path),
          var cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    if let t = tint(cg) { cg = t }

    let w = cg.width, h = cg.height
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let gctx = NSGraphicsContext(bitmapImageRep: rep) else { continue }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    let H = CGFloat(h), W = CGFloat(w)
    gctx.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))

    if h >= 128 {
        // sourceAtop paints only where the icon is already opaque, so the band
        // automatically follows the squircle's rounded bottom corners.
        let squircleBottom = H * 0.066, bandH = H * 0.253
        gctx.compositingOperation = .sourceAtop
        NSColor(calibratedWhite: 0, alpha: 0.60).setFill()
        NSRect(x: 0, y: 0, width: W, height: squircleBottom + bandH).fill()

        let fontSize = H * 0.150
        let font = NSFont(name: "Arial Black", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize, weight: .black)
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let str = NSAttributedString(string: label, attributes: [
            .font: font, .foregroundColor: NSColor.white, .paragraphStyle: para])
        let sz = str.size()
        gctx.compositingOperation = .sourceOver
        str.draw(in: NSRect(x: 0, y: squircleBottom + bandH/2 - sz.height/2, width: W, height: sz.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: path))
}
