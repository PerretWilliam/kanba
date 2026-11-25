import Testing
import Foundation
@testable import Kanban

/// Store reads KANBA_DATA at init, so these run one at a time, each in its own temp folder.
@MainActor @Suite(.serialized) struct StoreTests {
    static func tmp() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("kanba-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    /// A store on a fresh data folder, optionally seeded with boards.json content.
    func make(boards: [Board]? = nil, selected: UUID? = nil, legacy: [Card]? = nil, defaultsSelected: UUID? = nil) throws -> (Store, URL) {
        let dir = Self.tmp()
        if let boards { try JSONEncoder().encode(["boards": AnyEnc(boards), "selected": AnyEnc(selected ?? boards.first?.id ?? UUID())]).write(to: dir.appendingPathComponent("boards.json")) }
        if let legacy { try JSONEncoder().encode(legacy).write(to: dir.appendingPathComponent("cards.json")) }
        setenv("KANBA_DATA", dir.path, 1)
        if let defaultsSelected { UserDefaults.standard.set(defaultsSelected.uuidString, forKey: "selectedBoard") } else { UserDefaults.standard.removeObject(forKey: "selectedBoard") }
        return (Store(), dir)
    }
    struct AnyEnc: Encodable { let v: Encodable; init(_ v: Encodable) { self.v = v }; func encode(to e: Encoder) throws { try v.encode(to: e) } }

    func eventually(_ timeout: Double = 4, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; try? await Task.sleep(for: .milliseconds(40)) }
        return cond()
    }
    func card(_ title: String, _ status: String = "todo") -> Card { Card(title: title, status: status) }
    func saved(_ dir: URL) throws -> (boards: [Board], selected: UUID) {
        struct S: Decodable { var boards: [Board]; var selected: UUID }
        let s = try JSONDecoder().decode(S.self, from: Data(contentsOf: dir.appendingPathComponent("boards.json"))); return (s.boards, s.selected)
    }

    // MARK: init

    @Test func freshStartCreatesADefaultBoard() throws {
        let (s, dir) = try make()
        #expect(s.boards.count == 1 && s.board.name == "Mon Kanban")
        #expect(try saved(dir).boards.count == 1)
    }

    @Test func legacyCardsAreAdopted() throws {
        let (s, _) = try make(legacy: [card("old")])
        #expect(s.board.cards.map(\.title) == ["old"])
    }

    @Test func emptyFileShowsNoBoards() throws {
        let (s, _) = try make(boards: [])
        #expect(s.boards.isEmpty && s.topBoards.isEmpty && s.board.name == "" && s.board.cards.isEmpty)
        s.edit { $0.name = "x" }   // nothing to edit
        s.addPhase("no root")
        #expect(s.boards.isEmpty)
        s.add(Board(name: "first"))
        #expect(s.boards.count == 1)
    }

    @Test func selectionRules() throws {
        let a = Board(name: "A"), b = Board(name: "B")
        #expect(try make(boards: [a, b], selected: b.id).0.selected == b.id)
        #expect(try make(boards: [a, b], selected: b.id, defaultsSelected: a.id).0.selected == b.id)   // the file's selection wins at launch
        #expect(try make(boards: [a, b], selected: UUID()).0.selected == a.id)                          // stale id: first board
        #expect(try make(boards: [a, b], selected: a.id, defaultsSelected: UUID()).0.selected == a.id)
    }

    // MARK: toast

    @Test func toastAppearsAndFades() async throws {
        let (s, _) = try make()
        s.notify("one"); s.notify("two", actor: "claude")
        #expect(s.toast?.text == "two" && s.toast?.actor == "claude")
        #expect(await eventually(5) { s.toast == nil })
    }

    // MARK: cards

    @Test func cardsLifecycle() throws {
        let (s, dir) = try make()
        var c = card("a"); s.upsert(c)
        #expect(s.board.cards.count == 1 && s.toast?.text == "Carte « a » ajoutée")
        c.title = "b"; s.upsert(c)
        #expect(s.board.cards.map(\.title) == ["b"] && s.toast?.text == "Carte « b » modifiée")
        #expect(try saved(dir).boards[0].cards.count == 1)
        s.delete(c.id)
        #expect(s.board.cards.isEmpty && s.toast?.text == "Carte « b » supprimée")
        s.delete(UUID())
        #expect(s.toast?.text == "Carte «  » supprimée")
    }

    @Test func moveCardsToColumn() throws {
        let (s, _) = try make()
        let a = card("a"), b = card("b"); s.upsert(a); s.upsert(b)
        s.move([a.id.uuidString], to: "doing")
        #expect(s.board.cards[0].status == "doing" && s.toast?.text == "« a » déplacée vers « En cours »")
        s.move([a.id.uuidString, b.id.uuidString], to: "done")
        #expect(s.toast?.text == "2 cartes déplacées vers « Terminé »")
        s.move([], to: "nowhere")
        #expect(s.toast?.text == "0 carte déplacée vers «  »")
    }

    @Test func dropReorders() throws {
        let (s, _) = try make()
        let a = card("a"), b = card("b"), c = card("c"); [a, b, c].forEach(s.upsert)
        s.drop(c, to: "todo", before: a.id)
        #expect(s.board.cards.map(\.title) == ["c", "a", "b"] && s.toast?.text == "« c » réordonnée")
        s.drop(c, to: "doing", before: nil)
        #expect(s.board.cards.map(\.title) == ["a", "b", "c"] && s.board.cards[2].status == "doing" && s.toast?.text == "« c » déplacée vers « En cours »")
        s.drop(a, to: "todo", before: UUID())   // unknown anchor: end
        #expect(s.board.cards.last?.title == "a")
        s.drop(card("ghost"), to: "todo", before: nil)   // not on the board: nothing moves
        #expect(s.board.cards.count == 3)
    }

    @Test func moveToAnotherBoard() throws {
        let (s, _) = try make()
        var other = Board(name: "Other"); other.columns = [Column(id: "x", name: "X", color: .red), Column(id: "y", name: "en cours", color: .blue)]
        s.add(other); s.selected = s.boards[0].id
        let c = card("m", "doing"); s.upsert(c)
        s.move(c, toBoard: other.id)   // same-named column, case-insensitive
        #expect(s.board.cards.isEmpty && s.boards[1].cards.first?.status == "y" && s.toast?.text == "« m » déplacée vers « Other »")
        let d = card("n", "done"); s.upsert(d)
        s.move(d, toBoard: other.id)   // no such column name: first column
        #expect(s.boards[1].cards.last?.status == "x")
        s.move(d, toBoard: s.selected)      // same board
        s.move(d, toBoard: UUID())          // unknown board
        var noCols = Board(name: "Bare"); noCols.columns = []
        s.boards.append(noCols)
        s.move(c, toBoard: noCols.id)       // no column to land in
        #expect(s.boards[2].cards.isEmpty)
    }

    @Test func clearLastColumn() throws {
        let (s, _) = try make()
        [card("a", "done"), card("b", "done"), card("c")].forEach(s.upsert)
        s.clearLastColumn()
        #expect(s.board.cards.map(\.title) == ["c"] && s.toast?.text == "2 cartes supprimées")
        s.clearLastColumn()
        #expect(s.toast?.text == "0 carte supprimée")
        s.edit { $0.columns = [] }
        s.clearLastColumn()   // no column at all
    }

    // MARK: columns

    @Test func columnsLifecycle() throws {
        let (s, _) = try make()
        s.addColumn("Review")
        #expect(s.board.columns.count == 4 && s.toast?.text == "Colonne « Review » ajoutée")
        let id = s.board.columns[3].id
        s.renameColumn(id, "QA"); #expect(s.board.columns[3].name == "QA")
        s.renameColumn("zzz", "ignored")
        s.recolorColumn(id, .red); #expect(s.board.columns[3].color == .red && s.toast?.text == "Couleur de la colonne : rouge")
        s.recolorColumn("zzz", .red)
        s.upsert(card("x", id)); s.upsert(card("y", "todo"))
        s.deleteColumn(id)   // cards go to the left neighbour
        #expect(s.board.columns.count == 3 && s.board.cards.first { $0.title == "x" }?.status == "done" && s.toast?.text == "Colonne « QA » supprimée")
        s.deleteColumn("todo")   // first column: neighbour is the new first
        #expect(s.board.cards.first { $0.title == "y" }?.status == "doing")
        s.deleteColumn("zzz")
        s.deleteColumn("doing")
        s.deleteColumn("done")   // the last remaining column stays
        #expect(s.board.columns.count == 1)
    }

    // MARK: tabs

    @Test func tabsPhasesAndClosing() throws {
        let (s, _) = try make()
        let main = s.selected
        s.addPhase("P1")
        #expect(s.board.parent == main && s.rootID == main && s.phases.map(\.name) == ["P1"] && s.toast?.text == "Phase « P1 » créée")
        s.rename(s.selected, "P1b"); #expect(s.board.name == "P1b")
        s.rename(UUID(), "ignored")
        s.add(Board(name: "Second")); let second = s.selected
        #expect(s.topBoards.map(\.name) == ["Mon Kanban", "Second"] && s.toast?.text == "Tableau « Second » créé")
        s.add(Board(name: "Third")); let third = s.selected

        s.close(second)   // not the current tab: selection stays
        #expect(s.selected == third && s.topBoards.count == 2 && s.allTopBoards.count == 3 && s.toast?.text == "Tableau « Second » fermé : retrouvez-le dans Projets")
        s.close(third)    // current: moves to the left neighbour
        #expect(s.selected == main)
        s.close(main)     // last open tab closed: selection stays on it, nothing open
        #expect(s.topBoards.isEmpty && s.selected == main)
        s.close(UUID())
        s.reopen(second); #expect(s.selected == second && s.topBoards.map(\.name) == ["Second"])
        s.reopen(second)  // already open
        s.reopen(UUID())
        s.reopen(main); s.reopen(third)
        s.selected = main
        s.close(main)     // first tab closed: moves to the next
        #expect(s.selected == second)
    }

    @Test func removingBoards() throws {
        let (s, _) = try make()
        let main = s.selected
        s.addPhase("P"); let phase = s.selected
        s.add(Board(name: "B")); let b = s.selected
        s.remove(UUID())
        s.selected = phase
        s.remove(phase)   // a phase: back to its parent
        #expect(s.selected == main && s.boards.count == 2 && s.toast?.text == "Tableau « P » supprimé")
        s.selected = b
        s.remove(b)       // a tab: its left neighbour
        #expect(s.selected == main)
        s.addPhase("P2"); s.selected = main
        s.remove(main)    // takes its phases with it; nothing left: welcome page
        #expect(s.boards.isEmpty)
        s.add(Board(name: "X")); s.add(Board(name: "Y")); let y = s.selected
        s.close(s.boards[0].id); s.selected = y
        s.close(y)        // everything closed...
        s.remove(y)       // ...removing falls back on the first remaining board
        #expect(s.boards.count == 1 && s.selected == s.boards[0].id)
        s.selected = s.boards[0].id; s.remove(s.selected)
        #expect(s.boards.isEmpty)
    }

    // MARK: derived lists

    @Test func movePhasesTagsAgents() throws {
        let (s, _) = try make()
        let main = s.selected
        s.addPhase("P1"); let p1 = s.selected
        s.addPhase("P2"); let p2 = s.selected
        s.add(Board(name: "Solo")); let solo = s.selected
        s.selected = main
        let t = s.moveTargets
        #expect(t.map(\.name) == ["Mon Kanban", "Solo"] && !t[0].general && t[0].phases.map(\.id) == [p1, p2] && t[1].general && t[1].phases.isEmpty)
        s.selected = p1
        #expect(s.moveTargets[0].general && s.moveTargets[0].phases.map(\.id) == [p2])
        s.selected = solo
        #expect(s.moveTargets.map(\.name) == ["Mon Kanban"])   // current board without phases is left out
        #expect(t[0].id == main && !t[0].id.uuidString.isEmpty)

        s.upsert(Card(title: "c", status: "todo", tags: ["b", "a", "a"], agents: [Agent(name: "claude-code"), Agent(name: "me"), Agent(name: "Claude")]))
        #expect(s.allTags == ["a", "b"] && s.allAgents.map(\.key) == ["claude", "me"])
        #expect(Agents.all.first!.id == "me" && ColumnColor.red.id == .red && Priority.low.id == 0)
    }

    // MARK: external edits

    @Test func externalEditsReload() async throws {
        let (s, dir) = try make()
        let a = s.boards[0]
        var edited = a; edited.name = "Edited by AI"
        let other = Board(name: "Other")
        func write(_ boards: [Board], selected: UUID) throws {
            try JSONEncoder().encode(["boards": AnyEnc(boards), "selected": AnyEnc(selected)]).write(to: dir.appendingPathComponent("boards.json"), options: .atomic)
        }
        try write([edited, other], selected: other.id)   // new content and a new selection: the tab switches
        #expect(await eventually { s.boards.count == 2 })
        #expect(s.boards[0].name == "Edited by AI" && s.selected == other.id)

        s.selected = a.id
        try write([edited, other], selected: other.id)   // unchanged selection in the file: our tab stays
        try Data("not json".utf8).write(to: dir.appendingPathComponent("boards.json"))   // invalid: ignored
        try await Task.sleep(for: .milliseconds(300))
        #expect(s.boards.count == 2 && s.selected == a.id)

        try write([edited], selected: UUID())   // selection points nowhere: keep ours
        #expect(await eventually { s.boards.count == 1 })
        #expect(s.selected == a.id)
        try write([other], selected: other.id)   // our tab is gone: first board
        #expect(await eventually { s.boards.first?.name == "Other" })
        #expect(s.selected == other.id)
        try write([], selected: UUID())          // emptied: welcome page
        #expect(await eventually { s.boards.isEmpty })
    }

    @Test func filterIsScreenStateNeverSaved() throws {
        let a = Board(name: "A"), b = Board(name: "B")
        let (s, dir) = try make(boards: [a, b], selected: a.id)
        s.filter = ViewFilter(agent: "claude", query: "x")     // typing in the app never touches the disk
        let boardsJSON = try String(contentsOf: dir.appendingPathComponent("boards.json"), encoding: .utf8)
        #expect(!boardsJSON.contains("filter") && !boardsJSON.contains("claude"))
        s.selected = b.id                                      // another tab: filter reset
        #expect(s.filter.isEmpty)
    }

    // MARK: AI proposals (MCP)

    func propose(_ s: Store, actor: String = "claude-code", _ change: (inout [Board]) -> Void) {
        var new = s.proposal?.boards ?? s.boards; change(&new)
        s.propose(actor: actor, boards: new)
    }

    @Test func proposalAcceptedPartially() throws {
        let (s, _) = try make()
        s.upsert(card("keep"))
        propose(s) { $0[0].cards[0].title = "renamed"; $0[0].columns[0].name = "Todo"; $0[0].cards.append(Card(title: "added", status: "todo")) }
        #expect(s.review.count == 3 && s.toast?.text == "Claude propose 3 modifications" && s.toast?.actor == "claude-code")
        let first = s.review[0].id
        s.accept([first])
        #expect(s.proposal == nil && s.review.isEmpty && s.toast?.text == "1 modification appliquée")
        #expect(s.boards[0].columns[0].name == "Todo" && s.boards[0].cards.count == 1 && s.boards[0].cards[0].title == "keep")
    }

    @Test func proposalAcceptedWithNewBoardAndRefused() throws {
        let (s, _) = try make()
        let nb = Board(name: "AI board")
        propose(s, actor: "gemini-cli") { $0.append(nb) }
        #expect(s.toast?.text == "Gemini propose 1 modification")
        s.accept(Set(s.review.map(\.id)))
        #expect(s.selected == nb.id && s.toast?.text == "1 modification appliquée")

        propose(s) { $0.removeAll { $0.id == nb.id } }   // removes the selected board: back to the first
        s.accept(Set(s.review.map(\.id)))
        #expect(s.boards.count == 1 && s.selected == s.boards[0].id)

        propose(s) { $0[0].name = "x"; $0[0].closed = true }
        s.accept([])
        #expect(s.toast?.text == "Aucune modification appliquée" && s.boards[0].name == "Mon Kanban")

        propose(s) { $0[0].name = "again" }
        s.reject()
        #expect(s.proposal == nil && s.toast?.text == "Modifications refusées")
        s.reject(); s.accept([UUID()])   // nothing pending: no-ops
        #expect(s.boards[0].name == "Mon Kanban")
    }

    @Test func proposalsBuildOnEachOtherAndCancelOut() throws {
        let (s, _) = try make()
        propose(s) { $0[0].name = "p" }
        propose(s) { $0[0].columns[0].name = "Q" }   // a second call adds to the pending proposal, same base
        #expect(s.review.count == 2 && s.proposal?.base[0].name == "Mon Kanban")
        propose(s) { $0[0].name = "Mon Kanban"; $0[0].columns[0].name = "À faire" }   // back to the start: nothing left to review
        #expect(s.proposal == nil && s.review.isEmpty)
    }

    @Test func inPlaceEditAndAddedFileAreDetected() async throws {
        let (s, dir) = try make(boards: [Board(name: "A")])
        let url = dir.appendingPathComponent("boards.json")
        let h = try FileHandle(forWritingTo: url)   // edited in place: the file's inode stays, the folder sees nothing
        let edited = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\"A\"", with: "\"B\"")
        try h.truncate(atOffset: 0); try h.write(contentsOf: Data(edited.utf8)); try h.close()
        #expect(await eventually { s.boards.first?.name == "B" })
        try FileManager.default.removeItem(at: url)
        let other = Board(name: "dropped in")   // a boards.json added to the folder is picked up
        try JSONEncoder().encode(["boards": AnyEnc([other]), "selected": AnyEnc(other.id)]).write(to: url)
        #expect(await eventually { s.boards.first?.name == "dropped in" })
    }

    @Test func movingTheDataFolder() throws {
        defer { UserDefaults.standard.removeObject(forKey: "dataFolder") }
        let (s, old) = try make(boards: [Board(name: "A")])
        s.move(to: old)   // same folder: nothing
        #expect(s.toast == nil)
        let empty = Self.tmp().appendingPathComponent("new")   // does not exist yet: gets a copy of the boards
        s.move(to: empty)
        #expect(s.dir == empty)
        #expect(try saved(empty).boards.first?.name == "A")
        #expect(UserDefaults.standard.string(forKey: "dataFolder") == empty.path)
        s.edit { $0.name = "A2" }
        #expect(try saved(empty).boards.first?.name == "A2")
        #expect(try saved(old).boards.first?.name == "A")   // the old folder is left alone
        let full = Self.tmp()   // already holds boards: they win
        let b = Board(name: "existing")
        try JSONEncoder().encode(["boards": AnyEnc([b]), "selected": AnyEnc(b.id)]).write(to: full.appendingPathComponent("boards.json"))
        s.move(to: full)
        #expect(s.boards.map(\.name) == ["existing"] && s.selected == b.id)
    }
}
