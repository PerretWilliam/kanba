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

    private func save() { try? JSONEncoder().encode(cards).write(to: url, options: .atomic) }

    func upsert(_ card: Card) {
        if let i = cards.firstIndex(where: { $0.id == card.id }) { cards[i] = card } else { cards.append(card) }
    }

    func move(_ ids: [String], to status: Status) {
        for i in cards.indices where ids.contains(cards[i].id.uuidString) { cards[i].status = status }
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

// MARK: - Main view

struct ContentView: View {
    @StateObject private var store = Store()
    @State private var editing: Card?
    @State private var filter: Priority?
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 14) {
                ForEach(Status.allCases) { status in
                    ColumnView(status: status, cards: cards(in: status),
                               onEdit: { editing = $0 },
                               onAdd: { editing = Card(status: status) },
                               onDrop: { store.move($0, to: status) })
                }
            }
            .padding([.horizontal, .bottom], 14)
            .frame(maxHeight: .infinity)
        }
        .background(.background)
        .sheet(item: $editing) { card in
            EditView(card: card, isNew: !store.cards.contains { $0.id == card.id },
                     onSave: store.upsert,
                     onDelete: { id in store.cards.removeAll { $0.id == id } })
        }
        .confirmationDialog("Supprimer toutes les cartes terminées ?", isPresented: $confirmClear) {
            Button("Supprimer", role: .destructive) { store.cards.removeAll { $0.status == .done } }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Logo().fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                .frame(width: 22, height: 22)
            Text("Kanban").font(.title3.weight(.semibold))
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Menu {
                        Picker("Priorité", selection: $filter) {
                            Text("Toutes").tag(Priority?.none)
                            ForEach(Priority.allCases) { Text($0.label).tag(Optional($0)) }
                        }.pickerStyle(.inline)
                    } label: {
                        icon("line.3.horizontal.decrease", filter == nil ? .primary : .accentColor)
                    }
                    .menuStyle(.button).menuIndicator(.hidden).help("Filtrer par priorité")
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

    private func icon(_ name: String, _ tint: Color) -> some View {
        Image(systemName: name).font(.system(size: 15, weight: .medium)).foregroundStyle(tint)
            .frame(width: 20, height: 20)
    }

    private func iconButton(_ name: String, _ tip: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(name, tint) }.help(tip)
    }

    private func cards(in status: Status) -> [Card] {
        store.cards
            .filter { $0.status == status && (filter == nil || $0.priority == filter) }
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
    let onEdit: (Card) -> Void
    let onAdd: () -> Void
    let onDrop: ([String]) -> Void
    @State private var targeted = false

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
                LazyVStack(spacing: 8) {
                    ForEach(cards) { card in
                        CardView(card: card)
                            .onTapGesture { onEdit(card) }
                            .draggable(card.id.uuidString)
                    }
                }
                .padding([.horizontal, .bottom], 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(status.color.opacity(targeted ? 0.2 : 0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .dropDestination(for: String.self) { ids, _ in onDrop(ids); return true } isTargeted: { targeted = $0 }
    }
}

struct CardView: View {
    let card: Card

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10).padding(.leading, 16).padding(.trailing, 10)
        .background(.background.shadow(.drop(color: .black.opacity(0.08), radius: 5, y: 2)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(card.priority.color).frame(width: 4).padding(.vertical, 8).padding(.leading, 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.quaternary.opacity(0.6)))
        .opacity(card.status == .done ? 0.6 : 1)
        .contentShape(Rectangle())
    }
}

// MARK: - Form

struct EditView: View {
    @State var card: Card
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
            field("Priorité") {
                Picker("", selection: $card.priority) {
                    ForEach(Priority.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: .infinity)
            }
            field("Statut") {
                Picker("", selection: $card.status) {
                    ForEach(Status.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: .infinity)
            }
            HStack {
                Toggle("Échéance", isOn: Binding(
                    get: { card.due != nil },
                    set: { card.due = $0 ? (card.due ?? .now) : nil }))
                Spacer()
                if let due = card.due {
                    DatePicker("", selection: Binding(get: { due }, set: { card.due = $0 }),
                               displayedComponents: .date).labelsHidden()
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
