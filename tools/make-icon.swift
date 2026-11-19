// Renders Icon.icns: indigo squircle with a mini kanban (three columns of cards). Usage: swift tools/make-icon.swift
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
    NSGradient(colors: [NSColor(red: 0.42, green: 0.40, blue: 0.98, alpha: 1), NSColor(red: 0.25, green: 0.18, blue: 0.78, alpha: 1)])!.draw(in: shape, angle: -90)
    // Three columns (translucent) holding 3, 2 and 1 cards (white).
    let inner = box.insetBy(dx: box.width * 0.17, dy: box.width * 0.17)
    let gap = inner.width * 0.07, cw = (inner.width - 2 * gap) / 3, pad = cw * 0.12, ch = cw * 0.56
    for (i, n) in [3, 2, 1].enumerated() {
        let col = NSRect(x: inner.minX + CGFloat(i) * (cw + gap), y: inner.minY, width: cw, height: inner.height)
        NSColor.white.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: col, xRadius: cw * 0.22, yRadius: cw * 0.22).fill()
        for k in 0..<n {
            let r = NSRect(x: col.minX + pad, y: col.maxY - pad - ch - CGFloat(k) * (ch + pad * 0.8), width: cw - 2 * pad, height: ch)
            NSColor.white.withAlphaComponent(0.96).setFill()
            NSBezierPath(roundedRect: r, xRadius: cw * 0.13, yRadius: cw * 0.13).fill()
        }
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
