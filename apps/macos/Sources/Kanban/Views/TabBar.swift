import SwiftUI

/// Phases (sub-boards) of the current tab, under the tab strip.
struct PhaseBar: View {
    let root: Board, phases: [Board], selected: UUID
    let onSelect: (UUID) -> Void, onRename: (Board) -> Void, onDelete: (Board) -> Void, onNew: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            chip(root, label: "Général")
            ForEach(phases) { p in
                chip(p, label: p.name).contextMenu {
                    Button("Renommer…") { onRename(p) }
                    Button("Supprimer la phase", role: .destructive) { onDelete(p) }
                }
            }
            Button(action: onNew) { Label("Phase", systemImage: "plus").font(.inter(11)) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Nouvelle phase")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).frame(height: 30)
        .overlay(alignment: .bottom) { Divider() }
        .animation(.snappy(duration: 0.2), value: phases.map(\.id))
    }

    private func chip(_ b: Board, label: String) -> some View {
        let on = b.id == selected
        return Button { onSelect(b.id) } label: {
            Text(label).font(.inter(11, on ? .medium : .regular)).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(on ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.clear), in: .capsule)
                .foregroundStyle(on ? Color.accentColor : .secondary)
        }.buttonStyle(.plain)
    }
}

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
        // Select on first click: a plain onTapGesture(count: 2) next to a single tap delays the single one
        // by the system double-click interval.
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(TapGesture(count: 2).onEnded(onRename))
        .onHover { hover = $0 }
        .contextMenu {
            Button("Renommer…", action: onRename)
            ForEach(BoardIO.Format.allCases, id: \.self) { f in Button("Exporter en \(f.label)…") { BoardIO.export(board, as: f) } }
            Divider()
            Button("Fermer", action: onClose)
        }
    }
}
