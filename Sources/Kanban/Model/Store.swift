import SwiftUI

// MARK: - Store (JSON in ~/Library/Application Support/Kanban)

@MainActor final class Store: ObservableObject {
    @Published var boards: [Board] = [] { didSet { save() } }
    @Published var selected = UUID() { didSet { save() } }

    private struct Saved: Codable { var boards: [Board]; var selected: UUID }
    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kanban")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private var url: URL { dir.appendingPathComponent("boards.json") }

    init() {
        if let s = try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: url)), !s.boards.isEmpty {
            boards = s.boards; selected = s.selected
        } else {
            // First launch after the tabs update: adopt the old single-board file.
            let old = (try? JSONDecoder().decode([Card].self, from: Data(contentsOf: dir.appendingPathComponent("cards.json")))) ?? []
            boards = [Board(name: "Mon Kanban", cards: old)]
        }
        if !boards.contains(where: { $0.id == selected }) { selected = boards[0].id }
    }

    private func save() { try? JSONEncoder().encode(Saved(boards: boards, selected: selected)).write(to: url, options: .atomic) }

    // MARK: Current board

    private var index: Int { boards.firstIndex { $0.id == selected } ?? 0 }
    var board: Board { boards[index] }
    var allTags: [String] { Array(Set(board.cards.flatMap(\.tags))).sorted() }

    /// Mutates the current board with a single assignment (= a single save).
    func edit(_ change: (inout Board) -> Void) { var b = boards; change(&b[index]); boards = b }

    func upsert(_ card: Card) {
        edit { b in
            if let i = b.cards.firstIndex(where: { $0.id == card.id }) { b.cards[i] = card } else { b.cards.append(card) }
        }
    }
    func delete(_ id: UUID) { edit { $0.cards.removeAll { $0.id == id } } }

    func move(_ ids: [String], to column: String) {
        withAnimation(.snappy(duration: 0.25)) {
            edit { b in for i in b.cards.indices where ids.contains(b.cards[i].id.uuidString) { b.cards[i].status = column } }
        }
    }

    func clearLastColumn() { edit { b in if let last = b.columns.last?.id { b.cards.removeAll { $0.status == last } } } }

    // MARK: Columns

    func addColumn(_ name: String) { withAnimation { edit { $0.columns.append(Column(name: name, color: .allCases.randomElement()!)) } } }
    func renameColumn(_ id: String, _ name: String) { edit { b in if let i = b.columns.firstIndex(where: { $0.id == id }) { b.columns[i].name = name } } }
    func recolorColumn(_ id: String, _ color: ColumnColor) { edit { b in if let i = b.columns.firstIndex(where: { $0.id == id }) { b.columns[i].color = color } } }

    /// Cards of a deleted column fall back to its left neighbour (or the new first column).
    func deleteColumn(_ id: String) {
        edit { b in
            guard b.columns.count > 1, let i = b.columns.firstIndex(where: { $0.id == id }) else { return }
            let target = b.columns[i == 0 ? 1 : i - 1].id
            for k in b.cards.indices where b.cards[k].status == id { b.cards[k].status = target }
            withAnimation { _ = b.columns.remove(at: i) }
        }
    }

    // MARK: Tabs

    func add(_ board: Board) { boards.append(board); selected = board.id }
    func rename(_ id: UUID, _ name: String) { if let i = boards.firstIndex(where: { $0.id == id }) { boards[i].name = name } }

    func close(_ id: UUID) {
        guard let i = boards.firstIndex(where: { $0.id == id }) else { return }
        boards.remove(at: i)
        if boards.isEmpty { boards = [Board(name: "Sans titre")] }
        if selected == id { selected = boards[max(i - 1, 0)].id }
    }
}
