import SwiftUI

struct ContentView: View {
    @StateObject private var store = Store()
    @State private var editing: Card?
    @State private var filter: Priority?
    @State private var filterTag: String?
    @State private var showFilter = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    // Custom drag (system drag-and-drop keeps a "flying" preview for ~0.5s after release)
    @State private var dragging: Card?
    @State private var dragPoint = CGPoint.zero
    @State private var frames: [Status: CGRect] = [:]
    @State private var confirmClear = false
    @State private var showTemplates = false
    @State private var pending: Template?

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 14) {
                ForEach(Status.allCases) { status in
                    ColumnView(status: status, cards: cards(in: status),
                               draggingID: dragging?.id, highlighted: dragging != nil && column(at: dragPoint) == status,
                               onEdit: { editing = $0 },
                               onAdd: { editing = Card(status: status) },
                               onFrame: { frames[status] = $0 },
                               onDrag: { card, point in dragging = card; dragPoint = point },
                               onDrop: { card, point in
                                   if let to = column(at: point), to != card.status { store.move([card.id.uuidString], to: to) }
                                   dragging = nil
                               })
                }
            }
            .padding([.horizontal, .bottom], 14)
            .frame(maxHeight: .infinity)
        }
        .coordinateSpace(name: "board")
        .pointerStyle(dragging != nil ? .grabActive : nil)
        .overlay {
            if let card = dragging {
                CardView(card: card)
                    .frame(width: max((frames[card.status]?.width ?? 300) - 24, 100))
                    .scaleEffect(1.03).rotationEffect(.degrees(1.5))
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                    .position(dragPoint)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: dragging != nil)
        .background(.background)
        .font(.inter(13))
        .sheet(item: $editing) { card in
            EditView(card: card, allTags: store.allTags, isNew: !store.cards.contains { $0.id == card.id },
                     onSave: store.upsert,
                     onDelete: { id in store.cards.removeAll { $0.id == id } })
        }
        .sheet(isPresented: $showTemplates) {
            TemplatesView { t in
                if store.cards.isEmpty { store.cards = t.makeCards() } else { pending = t }
            }
        }
        .confirmationDialog("Appliquer « \(pending?.name ?? "") » ?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("Remplacer le tableau", role: .destructive) { if let t = pending { store.cards = t.makeCards() } }
            Button("Ajouter au tableau") { if let t = pending { store.cards += t.makeCards() } }
        }
        .confirmationDialog("Supprimer toutes les cartes terminées ?", isPresented: $confirmClear) {
            Button("Supprimer", role: .destructive) { store.cards.removeAll { $0.status == .done } }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            LogoMark()
            Text("Kanban").font(.mono(18, .bold))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher", text: $query).textFieldStyle(.plain).focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Button("") { searchFocused = true }.keyboardShortcut("f").opacity(0).frame(width: 0)
            }
            .padding(.horizontal, 12).frame(width: 220, height: 36)
            .glassEffect(.regular, in: .capsule)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    IconButton("line.3.horizontal.decrease", "Filtrer",
                               filter == nil && filterTag == nil ? .primary : .accentColor) { showFilter = true }
                        .popover(isPresented: $showFilter, arrowEdge: .bottom) { FilterPanel(filter: $filter, tag: $filterTag, tags: store.allTags) }
                    IconButton("square.grid.2x2", "Modèles") { showTemplates = true }
                    IconButton("trash", "Supprimer les cartes terminées", .red) { confirmClear = true }
                    IconButton("plus", "Nouvelle carte", .accentColor) { editing = Card() }
                        .keyboardShortcut("n")
                }
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func column(at p: CGPoint) -> Status? { frames.first { $0.value.contains(p) }?.key }

    private func cards(in status: Status) -> [Card] {
        store.cards
            .filter { $0.status == status && (filter == nil || $0.priority == filter)
                && (filterTag == nil || $0.tags.contains(filterTag!))
                && (query.isEmpty || ([$0.title, $0.notes] + $0.tags).contains { $0.localizedStandardContains(query) }) }
            .sorted { a, b in
                a.priority != b.priority ? a.priority.rawValue > b.priority.rawValue
                    : (a.due ?? .distantFuture) < (b.due ?? .distantFuture)
            }
    }
}
