import SwiftUI

struct ContentView: View {
    @StateObject private var store = Store()
    @State private var sheet: Sheet?
    @State private var detailID: UUID?
    @FocusState private var searchFocused: Bool
    @State private var cardToDelete: Card?
    @State private var showFilter = false
    // Custom drag (system drag-and-drop keeps a "flying" preview for ~0.5s after release)
    @State private var dragging: Card?
    @State private var dragPoint = CGPoint.zero
    @State private var frames: [String: CGRect] = [:]
    @State private var cardFrames: [UUID: CGRect] = [:]
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
        Group { if store.topBoards.isEmpty { welcome } else { main } }
            .toolbar { toolbarItems }
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
                             onSave: store.upsert)
                case .new:
                    TemplatesView { store.add($0) }
                case .review:
                    ReviewView(store: store)
                case .name(let title, let text, let apply):
                    NameSheet(title: title, text: text, onSave: apply)
                }
            }
            .confirmationDialog("Supprimer la carte « \(cardToDelete?.title ?? "") » ?", isPresented: Binding(get: { cardToDelete != nil }, set: { if !$0 { cardToDelete = nil } }), presenting: cardToDelete) { c in
                Button("Supprimer", role: .destructive) { store.delete(c.id) }
            }
            .confirmationDialog("Supprimer toutes les cartes de « \(board.columns.last?.name ?? "") » ?", isPresented: $confirmClear) {
                Button("Supprimer", role: .destructive) { store.clearLastColumn() }
            }
            .confirmationDialog("Supprimer \(board.parent == nil ? "le tableau" : "la phase") « \(board.name) » ?", isPresented: $confirmDelete) {
                Button("Supprimer", role: .destructive) { store.remove(store.selected) }
            } message: { Text(board.parent == nil && !store.phases.isEmpty ? "Ses phases, colonnes et cartes seront supprimées." : "Ses colonnes et ses cartes seront supprimées.") }
            .onChange(of: store.selected) { detailID = nil }
    }

    /// "N to review" pill: opens the diff of what an AI client proposed.
    @ViewBuilder private var reviewButton: some View {
        if let p = store.proposal {
            Button { sheet = .review } label: {
                HStack(spacing: 6) {
                    ActorIcon(actor: p.actor).frame(width: 14, height: 14)
                    Text("\(store.review.count) à valider").font(.inter(12, .medium))
                }
                .padding(.horizontal, 6).contentShape(.rect)
            }
            .help("Revoir les modifications proposées par \(Toast.actorName(p.actor))")
        }
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
            TabBar(boards: store.topBoards, selected: store.rootID,
                   onSelect: { store.selected = $0 }, onClose: { store.close($0) },
                   onRename: { b in sheet = .name(title: "Renommer le tableau", text: b.name) { store.rename(b.id, $0) } },
                   onNew: { sheet = .new })
            if let root = store.boards.first(where: { $0.id == store.rootID }) {
                PhaseBar(root: root, phases: store.phases, selected: store.selected,
                         onSelect: { store.selected = $0 },
                         onRename: { b in sheet = .name(title: "Renommer la phase", text: b.name) { store.rename(b.id, $0) } },
                         onDelete: { store.remove($0.id) },
                         onNew: { sheet = .name(title: "Nouvelle phase", text: "") { store.addPhase($0) } })
            }
            // The card panel sits beside the columns (they shrink) so no column is ever hidden under it.
            HStack(alignment: .top, spacing: 0) {
                HStack(spacing: 14) {
                    ForEach(board.columns) { col in
                        ColumnView(column: col, isDone: isDone(col.id), canDelete: board.columns.count > 1,
                                   onRename: { sheet = .name(title: "Renommer la colonne", text: col.name) { store.renameColumn(col.id, $0) } },
                                   onColor: { store.recolorColumn(col.id, $0) },
                                   onDeleteColumn: { store.deleteColumn(col.id) },
                                   onClear: { confirmClear = true },
                                   cards: cards(in: col.id),
                                   draggingID: dragging?.id, highlighted: dragging != nil && column(at: dragPoint) == col.id,
                                   moveTargets: store.moveTargets,
                                   onMoveToBoard: { store.move($0, toBoard: $1) },
                                   onOpen: { detailID = $0.id },
                                   onEdit: { sheet = .edit($0) },
                                   onAdd: { sheet = .edit(Card(status: col.id)) },
                                   onFrame: { frames[col.id] = $0 },
                                   onCardFrame: { cardFrames[$0] = $1 },
                                   onDrag: { card, point in dragging = card; dragPoint = point },
                                   onDrop: { card, point in
                                       if let to = column(at: point) {
                                           // Insert before the first other card whose middle is below the drop point.
                                           let rest = cards(in: to).filter { $0.id != card.id }
                                           let i = rest.firstIndex { (cardFrames[$0.id]?.midY ?? .infinity) > point.y }
                                           let same = to == card.status && cards(in: to).firstIndex { $0.id == card.id } == (i ?? rest.count)
                                           if !same { store.drop(card, to: to, before: i.map { rest[$0].id }) }
                                       }
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
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
                .frame(maxHeight: .infinity)
                .id(store.selected)  // fresh subtree per tab: no card/column transitions between boards
                if let c = detailCard {
                    CardDetail(card: c, column: board.columns.first { $0.id == c.status }, isDone: isDone(c.status),
                               onEdit: { sheet = .edit(c) }, onDelete: { cardToDelete = c }, onClose: { detailID = nil })
                        .padding(EdgeInsets(top: 12, leading: 0, bottom: 14, trailing: 14)).transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: detailID)
        }
    }

    private var detailCard: Card? { detailID.flatMap { id in board.cards.first { $0.id == id } } }

    /// Window toolbar (the title bar space we already pay for): no separate header row.
    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        ToolbarSpacer(.flexible)
        ToolbarItemGroup(placement: .primaryAction) {
            reviewButton
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher", text: $store.filter.query).textFieldStyle(.plain).focused($searchFocused)
                if !store.filter.query.isEmpty {
                    Button { store.filter.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Button("") { searchFocused = true }.keyboardShortcut("f").opacity(0).frame(width: 0)
            }
            .padding(.horizontal, 10).frame(width: 200, height: 30)
            .background(.quaternary.opacity(0.5), in: .capsule)
            Menu {
                ForEach(store.allTopBoards) { b in
                    Button { store.reopen(b.id) } label: {
                        if b.id == store.rootID && b.closed != true { Label(b.name, systemImage: "checkmark") }
                        else { Text(b.closed == true ? "\(b.name) · fermé" : b.name) }
                    }
                }
                Divider()
                Button("Nouveau tableau…") { sheet = .new }
            } label: { bar("square.stack") }
                .help("Tous les projets")
            let active = store.filter.hasChips
            Button { showFilter = true } label: { bar("line.3.horizontal.decrease", active ? .accentColor : .primary) }
                .help("Filtrer").disabled(store.topBoards.isEmpty)
                .popover(isPresented: $showFilter, arrowEdge: .bottom) {
                    FilterPanel(filter: $store.filter.priority, tag: $store.filter.tag, agent: $store.filter.agent, tags: store.allTags, agents: store.allAgents)
                }
            Menu {
                ForEach(BoardIO.Format.allCases, id: \.self) { f in Button("Exporter en \(f.label)…") { BoardIO.export(board, as: f) } }
            } label: { bar("square.and.arrow.up") }
                .help("Exporter le tableau").disabled(store.topBoards.isEmpty)
            Button { confirmDelete = true } label: { bar("trash", .red) }
                .help("Supprimer le tableau").disabled(store.topBoards.isEmpty)
            Button { sheet = .edit(Card(status: board.columns[0].id)) } label: { bar("plus", .accentColor) }
                .help("Nouvelle carte").keyboardShortcut("n").disabled(store.topBoards.isEmpty)
        }
    }

    private func bar(_ name: String, _ tint: Color = .primary) -> some View {
        Image(systemName: name).font(.system(size: 14, weight: .medium)).foregroundStyle(tint).frame(width: 34, height: 30).contentShape(.rect)
    }

    private func column(at p: CGPoint) -> String? {
        let ids = Set(board.columns.map(\.id))
        return frames.first { ids.contains($0.key) && $0.value.contains(p) }?.key
    }

    private func cards(in column: String) -> [Card] {
        board.cards   // manual order = array order (drag to reorder; AI clients set it too)
            .filter { $0.status == column && store.filter.matches($0) }
    }
}
