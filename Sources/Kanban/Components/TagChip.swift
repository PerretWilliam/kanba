import SwiftUI

// MARK: - Tags

struct TagChip: View {
    let tag: String
    var on = true
    var tint: Color?
    private var color: Color {
        if let tint { return tint }
        let palette: [Color] = [.blue, .pink, .orange, .teal, .indigo, .mint, .brown, .cyan]
        return palette[tag.unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) & 0xFFFFFF } % palette.count]
    }
    var body: some View {
        Text(tag).font(.inter(11, .medium)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(on ? 0.16 : 0.05), in: Capsule())
            .opacity(on ? 1 : 0.55)
            .animation(.snappy(duration: 0.2), value: on)
    }
}
