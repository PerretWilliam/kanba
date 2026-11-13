import SwiftUI

// MARK: - Model

enum Status: String, Codable, CaseIterable, Identifiable {
    case todo, doing, done
    var id: Self { self }
    var label: String { ["todo": "À faire", "doing": "En cours", "done": "Terminé"][rawValue]! }
    var color: Color { switch self { case .todo: .gray; case .doing: .blue; case .done: .green } }
}

enum Priority: Int, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: Int { rawValue }
    var label: String { ["Basse", "Moyenne", "Haute"][rawValue] }
    var color: Color { [Color.green, .orange, .red][rawValue] }
}

struct Card: Identifiable, Codable {
    var id = UUID()
    var title = ""
    var notes = ""
    var priority = Priority.medium
    var due: Date?
    var status = Status.todo
    var tags: [String] = []
}

// Tolerant decoding so cards saved before a field existed still load.
extension Card {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .medium
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .todo
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

// MARK: - Store (JSON in ~/Library/Application Support/Kanban)

@MainActor final class Store: ObservableObject {
    @Published var cards: [Card] = [] { didSet { save() } }

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kanban")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cards.json")
    }()

    init() { cards = (try? JSONDecoder().decode([Card].self, from: Data(contentsOf: url))) ?? [] }

    var allTags: [String] { Array(Set(cards.flatMap(\.tags))).sorted() }

    private func save() { try? JSONEncoder().encode(cards).write(to: url, options: .atomic) }

    func upsert(_ card: Card) {
        if let i = cards.firstIndex(where: { $0.id == card.id }) { cards[i] = card } else { cards.append(card) }
    }

    func move(_ ids: [String], to status: Status) {
        var next = cards  // single assignment = single save
        for i in next.indices where ids.contains(next[i].id.uuidString) { next[i].status = status }
        withAnimation(.snappy(duration: 0.25)) { cards = next }
    }
}

// MARK: - App

@main struct KanbanApp: App {
    var body: some Scene {
        Window("", id: "main") {
            ContentView()
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .frame(minWidth: 760, minHeight: 440)
                .toolbar(removing: .title)
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1100, height: 700)
    }
}

// MARK: - Logo (three columns of different heights)

struct Logo: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width * 0.26, heights = [1.0, 0.65, 0.82]
        for (i, h) in heights.enumerated() {
            let x = r.minX + CGFloat(i) * (r.width - w) / 2
            p.addRoundedRect(in: CGRect(x: x, y: r.maxY - r.height * h, width: w, height: r.height * h),
                             cornerSize: CGSize(width: w / 2.5, height: w / 2.5))
        }
        return p
    }
}

struct LogoMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Logo().fill(.white).padding(6))
            .frame(width: 28, height: 28)
    }
}

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
        Text(tag).font(.caption.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(on ? 0.16 : 0.05), in: Capsule())
            .opacity(on ? 1 : 0.55)
            .animation(.snappy(duration: 0.2), value: on)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (v, p) in zip(subviews, arrange(b.width, subviews).points) {
            v.place(at: CGPoint(x: b.minX + p.x, y: b.minY + p.y), proposal: .unspecified)
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x = 0.0, y = 0.0, rowH = 0.0, maxW = 0.0
        var points: [CGPoint] = []
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            points.append(CGPoint(x: x, y: y))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxW = max(maxW, x - spacing)
        }
        return (CGSize(width: maxW, height: y + rowH), points)
    }
}

// MARK: - Main view

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
        .sheet(item: $editing) { card in
            EditView(card: card, allTags: store.allTags, isNew: !store.cards.contains { $0.id == card.id },
                     onSave: store.upsert,
                     onDelete: { id in store.cards.removeAll { $0.id == id } })
        }
        .confirmationDialog("Supprimer toutes les cartes terminées ?", isPresented: $confirmClear) {
            Button("Supprimer", role: .destructive) { store.cards.removeAll { $0.status == .done } }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            LogoMark()
            Text("Kanban").font(.title3.weight(.semibold))
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
                    iconButton("line.3.horizontal.decrease", "Filtrer",
                               filter == nil && filterTag == nil ? .primary : .accentColor) { showFilter = true }
                        .popover(isPresented: $showFilter, arrowEdge: .bottom) { filterPanel }
                    iconButton("trash", "Supprimer les cartes terminées", .red) { confirmClear = true }
                    iconButton("plus", "Nouvelle carte", .accentColor) { editing = Card() }
                        .keyboardShortcut("n")
                }
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Priorité").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            FlowLayout {
                ForEach(Priority.allCases) { p in
                    TagChip(tag: p.label, on: filter == p, tint: p.color)
                        .onTapGesture { filter = filter == p ? nil : p }
                }
            }
            if !store.allTags.isEmpty {
                Text("Tag").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                FlowLayout {
                    ForEach(store.allTags, id: \.self) { tag in
                        TagChip(tag: tag, on: filterTag == tag)
                            .onTapGesture { filterTag = filterTag == tag ? nil : tag }
                    }
                }
            }
            if filter != nil || filterTag != nil {
                Button("Réinitialiser") { filter = nil; filterTag = nil }
            }
        }
        .padding(16).frame(width: 300, alignment: .leading)
        .buttonStyle(.automatic).buttonBorderShape(.automatic).controlSize(.regular)
    }

    private func icon(_ name: String, _ tint: Color) -> some View {
        Image(systemName: name).font(.system(size: 15, weight: .medium)).foregroundStyle(tint)
            .frame(width: 20, height: 20)
    }

    private func iconButton(_ name: String, _ tip: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(name, tint) }.help(tip)
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

// MARK: - Column (only the card list scrolls)

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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(status.color).frame(width: 8, height: 8)
                Text(status.label).fontWeight(.semibold).foregroundStyle(status.color)
                Text("\(cards.count)").font(.caption.weight(.semibold)).foregroundStyle(status.color)
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
        .background(status.color.opacity(highlighted ? 0.2 : 0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: highlighted)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("board")) } action: { onFrame($0) }
    }
}

struct CardView: View {
    let card: Card
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(card.title).fontWeight(.medium).lineLimit(3)
                    .strikethrough(card.status == .done)
            }
            if !card.notes.isEmpty {
                Text(card.notes).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 8) {
                Text(card.priority.label).font(.caption.weight(.semibold)).foregroundStyle(card.priority.color)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(card.priority.color.opacity(0.15), in: Capsule())
                if let due = card.due {
                    let late = card.status != .done && due < Calendar.current.startOfDay(for: .now)
                    Label(due.formatted(.dateTime.day().month(.abbreviated)), systemImage: "calendar")
                        .font(.caption).foregroundStyle(late ? .red : .secondary)
                }
            }
            if !card.tags.isEmpty {
                FlowLayout(spacing: 4) { ForEach(card.tags, id: \.self) { TagChip(tag: $0) } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.background.shadow(.drop(color: .black.opacity(0.08), radius: 5, y: 2)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.quaternary.opacity(0.6)))
        .opacity(card.status == .done ? 0.6 : 1)
        .contentShape(Rectangle())
        .scaleEffect(hover ? 1.012 : 1)
        .animation(.easeOut(duration: 0.15), value: hover)
        .onHover { hover = $0 }
    }
}

// MARK: - Form

struct EditView: View {
    @State var card: Card
    let allTags: [String]
    @State private var newTag = ""
    @State private var showCalendar = false
    let isNew: Bool
    let onSave: (Card) -> Void
    let onDelete: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Nouvelle carte" : "Modifier la carte").font(.title3.weight(.semibold))
            field("Titre") { TextField("", text: $card.title).textFieldStyle(.roundedBorder) }
            field("Notes") {
                TextField("", text: $card.notes, axis: .vertical).lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }
            field("Tags") {
                FlowLayout {
                    ForEach(Array(Set(allTags + card.tags)).sorted(), id: \.self) { tag in
                        let on = card.tags.contains(tag)
                        TagChip(tag: tag, on: on).onTapGesture {
                            if on { card.tags.removeAll { $0 == tag } } else { card.tags.append(tag) }
                        }
                    }
                }
                TextField("Nouveau tag, puis Entrée", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let t = newTag.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty && !card.tags.contains(t) { card.tags.append(t) }
                        newTag = ""
                    }
            }
            field("Priorité") {
                Picker("", selection: $card.priority) {
                    ForEach(Priority.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).fixedSize().frame(maxWidth: .infinity, alignment: .leading)
            }
            field("Statut") {
                Picker("", selection: $card.status) {
                    ForEach(Status.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).fixedSize().frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Toggle("Échéance", isOn: Binding(
                    get: { card.due != nil },
                    set: { card.due = $0 ? (card.due ?? .now) : nil }))
                Spacer()
                if let due = card.due {
                    Button(due.formatted(.dateTime.day().month(.wide).year())) { showCalendar = true }
                        .buttonStyle(.glass)
                        .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                            DatePicker("", selection: Binding(get: { due }, set: { card.due = $0 }),
                                       displayedComponents: .date)
                                .datePickerStyle(.graphical).labelsHidden().padding(12)
                        }
                }
            }
            HStack {
                if !isNew { Button("Supprimer", role: .destructive) { onDelete(card.id); dismiss() } }
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") { onSave(card); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(card.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.large)
        }
        .multilineTextAlignment(.leading)
        .padding(24)
        .frame(width: 420)
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            content()
        }
    }
}
