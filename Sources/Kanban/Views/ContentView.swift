import SwiftUI

struct ContentView: View {
    @StateObject private var store = Store()
    @State private var sheet: Sheet?
    @State private var filter: Priority?
    @State private var filterTag: String?
    @State private var showFilter = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    // Custom drag (system drag-and-drop keeps a "flying" preview for ~0.5s after release)
    @State private var dragging: Card?
    @State private var dragPoint = CGPoint.zero
    @State private var frames: [String: CGRect] = [:]
    @State private var confirmClear = false
    @State private var confirmDelete = false

    private var board: Board { store.board }
    private func isDone(_ columnID: String) -> Bool { board.columns.count > 1 && board.columns.last?.id == columnID }

    enum Sheet: Identifiable {
        case edit(Card), new, review, name(title: String, text: String, apply: (String) -> Void)
        var id: String {
            switch self { case .edit(let c): "edit-\(c.id)"; case .new: "new"; case .review: "review"; case .name(let t, _, _): "name-\(t)" }
        }
    }

    var body: some View {
        Group { if store.boards.isEmpty { welcome } else { main } }
            .coordinateSpace(name: "board")
            .pointerStyle(dragging != nil ? .grabActive : nil)
            .overlay {
                if let card = dragging {
                    CardView(card: card, isDone: isDone(card.status))
                        .frame(width: max((frames[card.status]?.width ?? 300) - 24, 100))
                        .scaleEffect(1.03).rotationEffect(.degrees(1.5))
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                        .position(dragPoint)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                if let t = store.toast { ToastView(toast: t).padding(.bottom, 22).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .animation(.snappy(duration: 0.2), value: dragging != nil)
            .background(.background)
            .font(.inter(13))
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .edit(let card):
                    EditView(card: card, allTags: store.allTags, columns: board.columns,
                             isNew: !board.cards.contains { $0.id == card.id },
                             onSave: store.upsert, onDelete: store.delete)
                case .new:
                    TemplatesView { store.add($0) }
                case .review:
                    ReviewView(store: store)
                case .name(let title, let text, let apply):
                    NameSheet(title: title, text: text, onSave: apply)
                }
            }
            .confirmationDialog("Supprimer toutes les cartes de « \(board.columns.last?.name ?? "") » ?", isPresented: $confirmClear) {
                Button("Supprimer", role: .destructive) { store.clearLastColumn() }
            }
            .confirmationDialog("Supprimer le tableau « \(board.name) » ?", isPresented: $confirmDelete) {
                Button("Supprimer", role: .destructive) { store.close(store.selected) }
            } message: { Text("Ses colonnes et ses cartes seront supprimées.") }
            .onChange(of: store.selected) { filter = nil; filterTag = nil; query = "" }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
            Text("Bienvenue dans Kanba").font(.mono(26, .bold))
            Text("Organisez vos tâches en colonnes, ou laissez votre assistant IA le faire : vous validez chaque modification.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack(spacing: 10) {
                Button { sheet = .new } label: { Label("Nouveau tableau", systemImage: "plus").padding(.horizontal, 6) }
                    .buttonStyle(.borderedProminent).keyboardShortcut("n")
                Button { if let b = BoardIO.importBoard() { store.add(b) } } label: { Label("Importer", systemImage: "square.and.arrow.down").padding(.horizontal, 6) }
            }
            .controlSize(.large).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var main: some View {
        VStack(spacing: 0) {
            TabBar(boards: store.boards, selected: store.selected,
                   onSelect: { store.selected = $0 }, onClose: { store.close($0) },
                   onRename: { b in sheet = .name(title: "Renommer le tableau", text: b.name) { store.rename(b.id, $0) } },
                   onNew: { sheet = .new })
            header
            HStack(spacing: 14) {
                ForEach(board.columns) { col in
                    ColumnView(column: col, isDone: isDone(col.id), canDelete: board.columns.count > 1,
                               onRename: { sheet = .name(title: "Renommer la colonne", text: col.name) { store.renameColumn(col.id, $0) } },
                               onColor: { store.recolorColumn(col.id, $0) },
                               onDeleteColumn: { store.deleteColumn(col.id) },
                               onClear: { confirmClear = true },
                               cards: cards(in: col.id),
                               draggingID: dragging?.id, highlighted: dragging != nil && column(at: dragPoint) == col.id,
                               onEdit: { sheet = .edit($0) },
                               onAdd: { sheet = .edit(Card(status: col.id)) },
                               onFrame: { frames[col.id] = $0 },
                               onDrag: { card, point in dragging = card; dragPoint = point },
                               onDrop: { card, point in
                                   if let to = column(at: point), to != card.status { store.move([card.id.uuidString], to: to) }
                                   dragging = nil
                               })
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
                Button { sheet = .name(title: "Nouvelle colonne", text: "") { store.addColumn($0) } } label: {
                    Image(systemName: "plus").foregroundStyle(.secondary).frame(width: 34).frame(maxHeight: .infinity)
                        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain).help("Ajouter une colonne")
            }
            .padding([.horizontal, .bottom], 14)
            .frame(maxHeight: .infinity)
            .id(store.selected)  // fresh subtree per tab: no card/column transitions between boards
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            LogoMark()
            Text("Kanba").font(.mono(18, .bold))
            Spacer()
            if let p = store.proposal {
                Button { sheet = .review } label: {
                    HStack(spacing: 6) {
                        ActorIcon(actor: p.actor).frame(width: 14, height: 14)
                        Text("\(store.review.count) à valider").font(.inter(12, .medium))
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                }
                .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .capsule)
                .help("Revoir les modifications proposées par \(Toast.actorName(p.actor))")
                .transition(.scale.combined(with: .opacity))
            }
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
                    IconButton("square.and.arrow.up", "Exporter en JSON") { BoardIO.export(board) }
                    IconButton("trash", "Supprimer le tableau", .red) { confirmDelete = true }
                    IconButton("plus", "Nouvelle carte", .accentColor) { sheet = .edit(Card(status: board.columns[0].id)) }
                        .keyboardShortcut("n")
                }
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func column(at p: CGPoint) -> String? {
        let ids = Set(board.columns.map(\.id))
        return frames.first { ids.contains($0.key) && $0.value.contains(p) }?.key
    }

    private func cards(in column: String) -> [Card] {
        board.cards
            .filter { $0.status == column && (filter == nil || $0.priority == filter)
                && (filterTag == nil || $0.tags.contains(filterTag!))
                && (query.isEmpty || ([$0.title, $0.notes] + $0.tags).contains { $0.localizedStandardContains(query) }) }
            .sorted { a, b in
                a.priority != b.priority ? a.priority.rawValue > b.priority.rawValue
                    : (a.due ?? .distantFuture) < (b.due ?? .distantFuture)
            }
    }
}
