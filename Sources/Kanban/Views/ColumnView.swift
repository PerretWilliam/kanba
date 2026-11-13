import SwiftUI

// Only the card list scrolls, never the page.
struct ColumnView: View {
    let status: Status
    let cards: [Card]
    let draggingID: UUID?
    let highlighted: Bool
    let onEdit: (Card) -> Void
    let onAdd: () -> Void
    let onFrame: (CGRect) -> Void
    let onDrag: (Card, CGPoint) -> Void
    let onDrop: (Card, CGPoint) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(status.color).frame(width: 8, height: 8)
                Text(status.label).font(.mono(13, .bold)).foregroundStyle(status.color)
                Text("\(cards.count)").font(.inter(11, .semibold)).foregroundStyle(status.color)
                    .padding(.horizontal, 6).background(status.color.opacity(0.18), in: Capsule())
                Spacer()
                Button(action: onAdd) { Image(systemName: "plus") }
                    .buttonStyle(.borderless).foregroundStyle(status.color).help("Ajouter une carte dans « \(status.label) »")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(cards) { card in
                        CardView(card: card)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                            .opacity(draggingID == card.id ? 0.25 : 1)
                            .pointerStyle(draggingID != nil ? .grabActive : .grabIdle)
                            .onTapGesture { onEdit(card) }
                            .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("board"))
                                .onChanged { onDrag(card, $0.location) }
                                .onEnded { onDrop(card, $0.location) })
                    }
                }
                .padding([.horizontal, .bottom], 12)
                .animation(.snappy(duration: 0.25), value: cards.map(\.id))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(status.color.opacity(highlighted ? (scheme == .dark ? 0.28 : 0.2) : (scheme == .dark ? 0.16 : 0.09)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: highlighted)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("board")) } action: { onFrame($0) }
    }
}
