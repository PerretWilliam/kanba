import SwiftUI

/// Round header button; the glass style comes from the surrounding container.
struct IconButton: View {
    let name: String, tip: String, tint: Color, action: () -> Void

    init(_ name: String, _ tip: String, _ tint: Color = .primary, action: @escaping () -> Void) {
        self.name = name; self.tip = tip; self.tint = tint; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 15, weight: .medium)).foregroundStyle(tint)
                .frame(width: 20, height: 20)
        }
        .help(tip)
    }
}
