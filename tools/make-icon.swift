// Renders Icon.icns: graphite squircle with three white bars. Usage: swift tools/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let box = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let shape = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
    NSGradient(colors: [NSColor(white: 0.24, alpha: 1), NSColor(white: 0.09, alpha: 1)])!.draw(in: shape, angle: -90)
    // Bars: same proportions as the in-app Logo shape.
    let inner = box.insetBy(dx: box.width * 0.24, dy: box.width * 0.24)
    let w = inner.width * 0.26
    for (i, h) in [1.0, 0.65, 0.82].enumerated() {
        let x = inner.minX + CGFloat(i) * (inner.width - w) / 2
        let r = NSRect(x: x, y: inner.minY, width: w, height: inner.height * h)
        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: r, xRadius: w / 2.5, yRadius: w / 2.5).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = "Icon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
