import SwiftUI

/// Icon of an AI client / agent: its official logo (Simple Icons SVG, tinted) when we have one, else an SF symbol.
struct AgentIcon: View {
    let name: String
    private static var cache: [String: NSImage] = [:]

    private static func logo(_ slug: String) -> NSImage? {
        if let i = cache[slug] { return i }
        guard let svg = Logos.svg[slug], let i = NSImage(data: Data(svg.utf8)) else { return nil }
        i.isTemplate = true; cache[slug] = i; return i
    }

    /// Pre-tinted bitmap for menu items (menus ignore custom views and template tinting).
    static func menuImage(_ name: String, size: CGFloat = 14) -> NSImage {
        let k = Agents.kind(name)
        let base = k?.logo.flatMap(logo) ?? NSImage(systemSymbolName: k?.symbol ?? "sparkle", accessibilityDescription: nil) ?? NSImage()
        let tint = NSColor(k?.color ?? .secondary)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            base.draw(in: r); tint.set(); r.fill(using: .sourceAtop); return true
        }
    }

    var body: some View {
        let k = Agents.kind(name)
        if let slug = k?.logo, let img = Self.logo(slug) {
            Image(nsImage: img).renderingMode(.template).resizable().scaledToFit().foregroundStyle(k?.color ?? .primary)
        } else {
            Image(systemName: k?.symbol ?? "sparkle").resizable().scaledToFit().foregroundStyle(k?.color ?? .secondary)
        }
    }
}
