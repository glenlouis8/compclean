// Puts each raw screenshot on a soft gradient with a shadow, for the README.
// Usage: swift scripts/frame-shots.swift docs/images/raw docs/images
import AppKit

let args = CommandLine.arguments
let inDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "docs/images/raw")
let outDir = URL(fileURLWithPath: args.count > 2 ? args[2] : "docs/images")

// The icon's pink to violet, a little softer so the window stands out.
let top = NSColor(red: 0.96, green: 0.56, blue: 0.75, alpha: 1)
let bottom = NSColor(red: 0.45, green: 0.36, blue: 0.95, alpha: 1)

func frame(_ shot: NSImage) -> NSBitmapImageRep {
    let rep = shot.representations.first!
    let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
    let pad = max(w, h) * 0.09
    let size = NSSize(width: w + pad * 2, height: h + pad * 2)
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    let bg = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: pad * 0.5, yRadius: pad * 0.5)
    NSGradient(starting: top, ending: bottom)!.draw(in: bg, angle: -60)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
    shadow.shadowBlurRadius = pad * 0.45
    shadow.shadowOffset = NSSize(width: 0, height: -pad * 0.12)
    shadow.set()
    shot.draw(in: NSRect(x: pad, y: pad, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    return out
}

let files = try FileManager.default.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "png" }
for file in files {
    guard let img = NSImage(contentsOf: file) else { continue }
    let png = frame(img).representation(using: .png, properties: [:])!
    try png.write(to: outDir.appendingPathComponent(file.lastPathComponent))
    print("framed", file.lastPathComponent)
}
