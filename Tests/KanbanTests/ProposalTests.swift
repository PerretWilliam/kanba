import Testing
import Foundation
@testable import Kanban

@Suite struct ProposalTests {
    let cA = Column(id: "a", name: "A", color: .gray), cB = Column(id: "b", name: "B", color: .blue), cC = Column(id: "c", name: "C", color: .green)
    func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
    func card(_ n: Int, _ title: String, _ status: String) -> Card { Card(id: id(n), title: title, status: status) }
    func board(_ n: Int, _ name: String = "P", cols: [Column]? = nil, cards: [Card] = []) -> Board {
        Board(id: id(100 + n), name: name, columns: cols ?? [cA, cB, cC], cards: cards)
    }
    func applyAll(_ ch: [Change], _ boards: [Board]) -> [Board] { var b = boards; for c in ch { c.apply(&b) }; return b }
    func lines(_ c: Change) -> [String] { c.lines.map(\.label) }

    @Test func noChange() throws {
        let b = board(1, cards: [card(1, "t", "a")])
        #expect(Proposal.diff([b], [b]).isEmpty)
        let p = Proposal(actor: "claude", base: [b], boards: [b])
        #expect(p.changes.isEmpty)
        #expect(try JSONDecoder().decode(Proposal.self, from: JSONEncoder().encode(p)).actor == "claude")
    }

    @Test func boardAddedAndRemoved() {
        let b = board(1)
        let add = Proposal.diff([], [b])
        #expect(add.count == 1 && add[0].kind == .add && add[0].addedBoard == b.id)
        #expect(applyAll(add, []).map(\.id) == [b.id])
        #expect(applyAll(add, [b]).count == 1)   // already there: no duplicate
        let rm = Proposal.diff([b], [])
        #expect(rm[0].kind == .remove && applyAll(rm, [b]).isEmpty)
    }

    @Test func boardRenamedAndClosed() {
        let b = board(1, "Old"); var n = b; n.name = "New"; n.closed = true
        let ch = Proposal.diff([b], [n])
        #expect(ch.count == 2 && ch.allSatisfy { $0.kind == .edit })
        let out = applyAll(ch, [b])
        #expect(out[0].name == "New" && out[0].closed == true)
        #expect(applyAll(Proposal.diff([n], [b]), out)[0].closed == nil)
    }

    @Test func columns() {
        let b = board(1, cards: [card(1, "x", "b"), card(2, "y", "a")])
        var edited = cA; edited.name = "A2"; edited.color = .red
        let added = Column(id: "d", name: "D", color: .pink)
        var n = b; n.columns = [edited, added, cC]
        let ch = Proposal.diff([b], [n])
        #expect(ch.count == 3)
        let out = applyAll(ch, [b])[0]
        #expect(out.columns.map(\.id) == ["a", "d", "c"] && out.columns[0].name == "A2" && out.columns[0].color == .red)
        #expect(out.cards.first { $0.id == id(1) }?.status == "d")   // "b" was removed: cards fall to its left neighbour in the live board
        var n2 = b; n2.columns = [cB, cC]   // first column removed: cards go to the new first one
        let rm = Proposal.diff([b], [n2])
        #expect(applyAll(rm, [b])[0].cards.first { $0.id == id(2) }?.status == "b")
        // never removes the last column; changes on a missing board / column do nothing
        #expect(applyAll(rm, [Board(id: b.id, name: "P", columns: [cA])])[0].columns.count == 1)
        #expect(applyAll(ch, [board(9)]).count == 1)
        #expect(applyAll(ch, [Board(id: b.id, name: "P", columns: [cB, added])])[0].columns.map(\.id) == ["d"])   // 'a' edit skipped, 'd' not duplicated, 'b' removed
    }

    @Test func cardEdited() {
        let o = Card(id: id(1), title: "t", notes: "n", priority: .low, due: nil, status: "a", tags: ["x"], agents: [Agent(name: "me")])
        var c = o; c.title = "t2"; c.notes = "n2"; c.priority = .high; c.due = Date(timeIntervalSinceReferenceDate: 86400); c.status = "b"; c.tags = ["y"]; c.agents = [Agent(name: "claude", model: "m")]
        let b = board(1, cards: [o])
        let ch = Proposal.diff([b], [board(1, cards: [c])])
        #expect(ch.count == 1 && Set(lines(ch[0])) == ["Titre", "Colonne", "Priorité", "Échéance", "Tags", "Agents", "Notes"])
        #expect(applyAll(ch, [b])[0].cards[0] == c)
        let from = Card(id: id(1), title: "t", notes: "n", priority: .low, due: Date(timeIntervalSinceReferenceDate: 5), status: "a", agents: [Agent(name: "me")])
        let to = Card(id: id(1), title: "t", notes: "", priority: .low, due: nil, status: "a", agents: [])
        let ch2 = Proposal.diff([board(1, cards: [from])], [board(1, cards: [to])])
        #expect(ch2[0].lines.contains { $0.new == "aucune" } && ch2[0].lines.contains { $0.new == "aucun" } && ch2[0].lines.contains { $0.new == "(vide)" })
        var lost = o; lost.status = "zzz"   // a status pointing at a missing column falls back to the first column
        #expect(applyAll(Proposal.diff([b], [board(1, cards: [lost])]), [b])[0].cards[0].status == "a")
        #expect(applyAll(ch, [board(1)])[0].cards.isEmpty)   // card gone meanwhile: ignored
    }

    @Test func cardAddedAndRemoved() {
        var c = card(1, "new", "b"); c.due = Date(timeIntervalSinceReferenceDate: 0); c.tags = ["t"]; c.notes = "note"; c.agents = [Agent(name: "me")]
        let b = board(1)
        let add = Proposal.diff([b], [board(1, cards: [c])])
        #expect(add[0].kind == .add && Set(lines(add[0])) == ["Colonne", "Priorité", "Échéance", "Tags", "Agents", "Notes"])
        let out = applyAll(add, [b])
        #expect(out[0].cards == [c] && applyAll(add, out)[0].cards.count == 1)
        var bad = c; bad.status = "zzz"
        #expect(applyAll(Proposal.diff([b], [board(1, cards: [bad])]), [b])[0].cards[0].status == "a")
        #expect(Set(lines(Proposal.diff([b], [board(1, cards: [card(2, "p", "a")])])[0])) == ["Colonne", "Priorité"])
        let withCard = board(1, cards: [c])
        let rm = Proposal.diff([withCard], [b])
        #expect(rm[0].kind == .remove && applyAll(rm, [withCard])[0].cards.isEmpty)
    }

    @Test func cardMovedBetweenBoards() {
        let c = card(1, "m", "b")
        let b1 = board(1, "One", cards: [c]), b2 = board(2, "Two", cols: [cA])
        var moved = c; moved.status = "a"
        let n1 = board(1, "One"), n2 = board(2, "Two", cols: [cA], cards: [moved])
        let ch = Proposal.diff([b1, b2], [n1, n2])
        #expect(ch.count == 1 && Set(lines(ch[0])) == ["Tableau", "Colonne"] && ch[0].scope == "One")
        let out = applyAll(ch, [b1, b2])
        #expect(out[0].cards.isEmpty && out[1].cards.first?.title == "m")
        var odd = c; odd.status = "gone"   // destination lacks the card's column: first column
        #expect(applyAll(Proposal.diff([b1, b2], [n1, board(2, "Two", cols: [cA], cards: [odd])]), [b1, b2])[1].cards.first?.status == "a")
        #expect(applyAll(ch, [b2]).count == 1 && applyAll(ch, [board(1, "One"), b2])[1].cards.isEmpty && applyAll(ch, [b1])[0].cards.count == 1)
    }

    @Test func orderWithinColumn() {
        let cs = [card(1, "one", "a"), card(2, "two", "a"), card(3, "three", "b"), card(4, "four", "a")]
        let b = board(1, cards: cs)
        let ch = Proposal.diff([b], [board(1, cards: [cs[3], cs[2], cs[0], cs[1]])])
        #expect(ch.count == 1 && ch[0].title == "Ordre dans « A »")
        #expect(ch[0].lines[0].new == "1. four\n2. one\n3. two" && ch[0].lines[0].old == "1. one\n2. two\n3. four")
        #expect(applyAll(ch, [b])[0].cards.map(\.title) == ["four", "one", "three", "two"])
        let live = board(1, cards: [cs[0], cs[1], card(9, "extra", "a")])   // unlisted live cards keep their order, after
        #expect(applyAll(ch, [live])[0].cards.map(\.title) == ["one", "two", "extra"])
    }
}
