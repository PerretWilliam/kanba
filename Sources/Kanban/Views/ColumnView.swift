import SwiftUI

// Only the card list scrolls, never the page.
struct ColumnView: View {
    let column: Column
    let isDone: Bool
    let canDelete: Bool
    let onRename: () -> Void
    let onColor: (ColumnColor) -> Void
    let onDeleteColumn: () -> Void
    let onClear: () -> Void
    let cards: [Card]
    let draggingID: UUID?
    let highlighted: Bool
    let otherBoards: [(id: UUID, name: String)]
    let onMoveToBoard: (Card, UUID) -> Void
    let onEdit: (Card) -> Void
    let onAdd: () -> Void
    let onFrame: (CGRect) -> Void
    let onCardFrame: (UUID, CGRect) -> Void
    let onDrag: (Card, CGPoint) -> Void
    let onDrop: (Card, CGPoint) -> Void
    @Environment(\.colorScheme) private var scheme
    private var tint: Color { column.color.color }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(column.name).font(.mono(13, .bold)).foregroundStyle(tint)
                Text("\(cards.count)").font(.inter(11, .semibold)).foregroundStyle(tint)
                    .padding(.horizontal, 6).background(tint.opacity(0.18), in: Capsule())
                Spacer()
                Button(action: onAdd) { Image(systemName: "plus") }
                    .buttonStyle(.borderless).foregroundStyle(tint).help("Ajouter une carte dans « \(column.name) »")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Renommer…", action: onRename)
                Menu("Couleur") {
                    ForEach(ColumnColor.allCases) { c in Button(c.label) { onColor(c) } }
                }
                Divider()
                if isDone { Button("Vider la colonne", role: .destructive, action: onClear) }
                Button("Supprimer la colonne", role: .destructive, action: onDeleteColumn).disabled(!canDelete)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(cards) { card in
                        CardView(card: card, isDone: isDone)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                            .opacity(draggingID == card.id ? 0.25 : 1)
                            .pointerStyle(draggingID != nil ? .grabActive : .grabIdle)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("board")) } action: { onCardFrame(card.id, $0) }
                            .onTapGesture { onEdit(card) }
                            .contextMenu {
                                Button("Modifier…") { onEdit(card) }
                                if !otherBoards.isEmpty {
                                    Menu("Déplacer vers le tableau") {
                                        ForEach(otherBoards, id: \.id) { t in Button(t.name) { onMoveToBoard(card, t.id) } }
                                    }
                                }
                            }
                            .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("board"))
                                .onChanged { onDrag(card, $0.location) }
                                .onEnded { onDrop(card, $0.location) })
                    }
                }
                .padding([.horizontal, .bottom], 12)
                .animation(.snappy(duration: 0.25), value: cards.map(\.id))
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tint.opacity(highlighted ? (scheme == .dark ? 0.28 : 0.2) : (scheme == .dark ? 0.16 : 0.09)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: highlighted)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("board")) } action: { onFrame($0) }
    }
}
