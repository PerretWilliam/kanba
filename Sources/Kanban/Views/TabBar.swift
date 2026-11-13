import SwiftUI

/// VS Code–style strip of open boards, at the very top of the window.
struct TabBar: View {
    let boards: [Board]
    let selected: UUID
    let onSelect: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onRename: (Board) -> Void
    let onNew: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(boards) { b in
                TabItem(board: b, selected: b.id == selected, onSelect: { onSelect(b.id) },
                        onClose: { onClose(b.id) }, onRename: { onRename(b) })
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
            Button(action: onNew) { Image(systemName: "plus").font(.system(size: 12, weight: .medium)) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).padding(.horizontal, 12)
                .help("Nouveau tableau")
            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .background(.quaternary.opacity(0.35))
        .overlay(alignment: .bottom) { Divider() }
        .animation(.snappy(duration: 0.2), value: boards.map(\.id))
    }
}

private struct TabItem: View {
    let board: Board, selected: Bool
    let onSelect: () -> Void, onClose: () -> Void, onRename: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.3x1").font(.system(size: 11)).foregroundStyle(selected ? Color.accentColor : .secondary)
            Text(board.name).font(.inter(12, selected ? .medium : .regular)).lineLimit(1)
                .foregroundStyle(selected ? .primary : .secondary)
            Spacer(minLength: 12)
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .opacity(selected || hover ? 1 : 0).help("Fermer")
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 140, maxWidth: 220, maxHeight: .infinity)
        .background(selected ? AnyShapeStyle(.background) : AnyShapeStyle(hover ? Color.primary.opacity(0.05) : .clear))
        .overlay(alignment: .top) { if selected { Rectangle().fill(Color.accentColor).frame(height: 2) } }
        .overlay(alignment: .trailing) { Rectangle().fill(.quaternary).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onRename)
        .onTapGesture(perform: onSelect)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Renommer…", action: onRename)
            Button("Exporter en JSON…") { BoardIO.export(board) }
            Divider()
            Button("Fermer", action: onClose)
        }
    }
}
