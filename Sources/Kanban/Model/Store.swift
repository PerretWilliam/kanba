import SwiftUI

// MARK: - Store (JSON in ~/Library/Application Support/Kanban)

@MainActor final class Store: ObservableObject {
    @Published var boards: [Board] = [] { didSet { save() } }
    // Saved with the boards so external tools (MCP) always know which tab is on screen.
    @Published var selected = UUID() { didSet { UserDefaults.standard.set(selected.uuidString, forKey: "selectedBoard"); save() } }

    @Published var toast: Toast?
    @Published var proposal: Proposal?     // pending changes from an AI client (proposal.json)
    @Published var review: [Change] = []   // its diff against the base the AI started from
    private var toastTask: Task<Void, Never>?
    private var lastProposalData: Data?

    /// Short message at the bottom of the window. `actor` nil = the user, else the AI client's name.
    func notify(_ text: String, actor: String? = nil) {
        withAnimation(.snappy(duration: 0.25)) { toast = Toast(text: text, actor: actor) }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.8))
            if !Task.isCancelled { withAnimation(.snappy(duration: 0.25)) { toast = nil } }
        }
    }
    private func plural(_ n: Int, _ w: String) -> String { "\(n) \(w)\(n > 1 ? "s" : "")" }

    private struct Saved: Codable { var boards: [Board]; var selected: UUID }
    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kanban")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private var url: URL { dir.appendingPathComponent("boards.json") }
    private var proposalURL: URL { dir.appendingPathComponent("proposal.json") }

    init() {
        if let s = try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: url)), !s.boards.isEmpty {
            boards = s.boards; selected = s.selected; fileSelected = s.selected
        } else {
            // First launch after the tabs update: adopt the old single-board file.
            let old = (try? JSONDecoder().decode([Card].self, from: Data(contentsOf: dir.appendingPathComponent("cards.json")))) ?? []
            boards = [Board(name: "Mon Kanban", cards: old)]
        }
        if let id = UserDefaults.standard.string(forKey: "selectedBoard").flatMap(UUID.init), boards.contains(where: { $0.id == id }) { selected = id }
        if !boards.contains(where: { $0.id == selected }) { selected = boards[0].id }
        save()  // file's "selected" may be stale (e.g. taken from UserDefaults above)
        watch()
        loadProposal()
    }

    private var fileSelected: UUID?      // "selected" as last seen in the file: an external change to it switches the tab
    private var lastData: Data?          // last bytes we wrote or loaded; lets us ignore our own file events
    private var watcher: DispatchSourceFileSystemObject?

    private func save() {
        guard let d = try? JSONEncoder().encode(Saved(boards: boards, selected: selected)) else { return }
        lastData = d; fileSelected = selected
        try? d.write(to: url, options: .atomic)
    }

    /// Live-reloads boards.json when another process (e.g. an AI agent) edits it.
    /// Watches the directory, not the file: atomic writes replace the inode.
    private func watch() {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in self?.reload(); self?.loadProposal() }
        src.setCancelHandler { Darwin.close(fd) }
        src.resume()
        watcher = src
    }

    private func reload() {
        guard let d = try? Data(contentsOf: url), d != lastData,
              let s = try? JSONDecoder().decode(Saved.self, from: d), !s.boards.isEmpty else { return }
        lastData = d
        let target = s.selected != fileSelected && s.boards.contains { $0.id == s.selected } ? s.selected : selected
        fileSelected = s.selected
        withAnimation {
            selected = s.boards.contains { $0.id == target } ? target : s.boards[0].id
            boards = s.boards
        }
    }

    // MARK: AI proposals

    private func loadProposal() {
        guard let d = try? Data(contentsOf: proposalURL) else {
            if proposal != nil { proposal = nil; review = [] }
            lastProposalData = nil; return
        }
        guard d != lastProposalData, let p = try? JSONDecoder().decode(Proposal.self, from: d) else { return }
        lastProposalData = d
        let changes = p.changes
        if changes.isEmpty { finishProposal(); return }
        withAnimation { proposal = p; review = changes }
        notify("\(Toast.actorName(p.actor)) propose \(plural(changes.count, "modification"))", actor: p.actor)
    }

    private func finishProposal() {
        try? FileManager.default.removeItem(at: proposalURL)
        lastProposalData = nil; proposal = nil; review = []
    }

    /// Applies the ticked changes to the live boards; the others are dropped.
    func accept(_ ids: Set<UUID>) {
        guard let p = proposal else { return }
        let chosen = review.filter { ids.contains($0.id) }
        var b = boards
        for c in chosen { c.apply(&b) }
        withAnimation {
            boards = b
            if let id = chosen.compactMap(\.addedBoard).last, b.contains(where: { $0.id == id }) { selected = id }
            if !boards.contains(where: { $0.id == selected }) { selected = boards[0].id }
        }
        finishProposal()
        notify(chosen.isEmpty ? "Aucune modification appliquée" : "\(plural(chosen.count, "modification")) appliquée\(chosen.count > 1 ? "s" : "")", actor: p.actor)
    }

    func reject() {
        guard let p = proposal else { return }
        finishProposal()
        notify("Modifications refusées", actor: p.actor)
    }

    // MARK: Current board

    private var index: Int { boards.firstIndex { $0.id == selected } ?? 0 }
    var board: Board { boards[index] }
    var allTags: [String] { Array(Set(board.cards.flatMap(\.tags))).sorted() }

    /// Mutates the current board with a single assignment (= a single save).
    func edit(_ change: (inout Board) -> Void) { var b = boards; change(&b[index]); boards = b }

    func upsert(_ card: Card) {
        let isNew = !board.cards.contains { $0.id == card.id }
        defer { notify("Carte « \(card.title) » \(isNew ? "ajoutée" : "modifiée")") }
        edit { b in
            if let i = b.cards.firstIndex(where: { $0.id == card.id }) { b.cards[i] = card } else { b.cards.append(card) }
        }
    }
    func delete(_ id: UUID) {
        let title = board.cards.first { $0.id == id }?.title ?? ""
        edit { $0.cards.removeAll { $0.id == id } }
        notify("Carte « \(title) » supprimée")
    }

    func move(_ ids: [String], to column: String) {
        let name = board.columns.first { $0.id == column }?.name ?? ""
        let titles = board.cards.filter { ids.contains($0.id.uuidString) }.map(\.title)
        notify(titles.count == 1 ? "« \(titles[0]) » déplacée vers « \(name) »" : "\(plural(titles.count, "carte")) déplacée\(titles.count > 1 ? "s" : "") vers « \(name) »")
        withAnimation(.snappy(duration: 0.25)) {
            edit { b in for i in b.cards.indices where ids.contains(b.cards[i].id.uuidString) { b.cards[i].status = column } }
        }
    }

    func clearLastColumn() {
        let n = board.cards.filter { $0.status == board.columns.last?.id }.count
        edit { b in if let last = b.columns.last?.id { b.cards.removeAll { $0.status == last } } }
        notify("\(plural(n, "carte")) supprimée\(n > 1 ? "s" : "")")
    }

    // MARK: Columns

    func addColumn(_ name: String) {
        withAnimation { edit { $0.columns.append(Column(name: name, color: .allCases.randomElement()!)) } }
        notify("Colonne « \(name) » ajoutée")
    }
    func renameColumn(_ id: String, _ name: String) {
        edit { b in if let i = b.columns.firstIndex(where: { $0.id == id }) { b.columns[i].name = name } }
        notify("Colonne renommée « \(name) »")
    }
    func recolorColumn(_ id: String, _ color: ColumnColor) {
        edit { b in if let i = b.columns.firstIndex(where: { $0.id == id }) { b.columns[i].color = color } }
        notify("Couleur de la colonne : \(color.label.lowercased())")
    }

    /// Cards of a deleted column fall back to its left neighbour (or the new first column).
    func deleteColumn(_ id: String) {
        let name = board.columns.first { $0.id == id }?.name ?? ""
        let before = board.columns.count
        defer { if board.columns.count < before { notify("Colonne « \(name) » supprimée") } }
        edit { b in
            guard b.columns.count > 1, let i = b.columns.firstIndex(where: { $0.id == id }) else { return }
            let target = b.columns[i == 0 ? 1 : i - 1].id
            for k in b.cards.indices where b.cards[k].status == id { b.cards[k].status = target }
            withAnimation { _ = b.columns.remove(at: i) }
        }
    }

    // MARK: Tabs

    func add(_ board: Board) { boards.append(board); selected = board.id; notify("Tableau « \(board.name) » créé") }
    func rename(_ id: UUID, _ name: String) {
        if let i = boards.firstIndex(where: { $0.id == id }) { boards[i].name = name }
        notify("Tableau renommé « \(name) »")
    }

    func close(_ id: UUID) {
        guard let i = boards.firstIndex(where: { $0.id == id }) else { return }
        let name = boards[i].name
        defer { notify("Tableau « \(name) » fermé") }
        boards.remove(at: i)
        if boards.isEmpty { boards = [Board(name: "Sans titre")] }
        if selected == id { selected = boards[max(i - 1, 0)].id }
    }
}
