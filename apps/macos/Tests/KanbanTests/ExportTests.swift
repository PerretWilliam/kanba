import Testing
import Foundation
@testable import Kanban

@Suite struct ExportTests {
    func board() -> Board {
        var b = Board(name: "Proj")
        b.cards = [
            Card(title: "A \"q\"", notes: "l1\n\nl2", priority: .high, due: Date(timeIntervalSinceReferenceDate: 0), status: "todo", tags: ["x", "y"],
                 agents: [Agent(name: "claude", model: "Opus 5.5", effort: "high"), Agent(name: "me")]),
            Card(title: "B", status: "done"),
        ]
        return b
    }

    @Test func formats() {
        #expect(BoardIO.Format.allCases.map(\.ext) == ["json", "csv", "md"])
        #expect(BoardIO.Format.allCases.map(\.label) == ["JSON", "CSV", "Markdown"])
        #expect(BoardIO.day(nil) == "" && BoardIO.day(Date(timeIntervalSinceReferenceDate: 0)) == "2001-01-01")
    }

    @Test func csv() {
        let s = BoardIO.csv(board())
        #expect(s.hasPrefix("\u{FEFF}Colonne,Titre,Notes,Priorité,Échéance,Tags,Agents\r\n"))
        #expect(s.contains("\"À faire\",\"A \"\"q\"\"\",\"l1\n\nl2\",\"Haute\",\"2001-01-01\",\"x, y\",\"Claude · Opus 5.5 · Élevé; Moi\""))
        #expect(s.contains("\"Terminé\",\"B\""))
    }

    @Test func markdown() {
        let s = BoardIO.markdown(board())
        #expect(s.hasPrefix("# Proj\n\n## À faire\n\n- [ ] **A \"q\"** — Priorité : Haute · échéance 2001-01-01 · #x #y · agents : Claude · Opus 5.5 · Élevé, Moi\n  l1\n  l2\n"))
        #expect(s.contains("- [x] **B** — Priorité : Moyenne\n"))
    }

    @Test func jsonRoundTrip() throws {
        let b = board()
        let data = try BoardIO.data(b, as: .json)
        let back = try #require(BoardIO.decode(data))
        #expect(back.name == "Proj" && back.cards.count == 2 && back.id != b.id)
        #expect(back.cards[0].agents == b.cards[0].agents && back.cards[0].due == b.cards[0].due)
        #expect(String(decoding: try BoardIO.data(b, as: .csv), as: UTF8.self) == BoardIO.csv(b))
        #expect(String(decoding: try BoardIO.data(b, as: .markdown), as: UTF8.self) == BoardIO.markdown(b))
    }

    @Test func decodeRejectsAndRepairs() throws {
        #expect(BoardIO.decode(Data("nope".utf8)) == nil)
        #expect(BoardIO.decode(Data(#"{"format":"other","version":1,"name":"x","columns":[{"id":"a","name":"A","color":"red"}],"cards":[]}"#.utf8)) == nil)
        #expect(BoardIO.decode(Data(#"{"format":"kanban","version":1,"name":"x","columns":[],"cards":[]}"#.utf8)) == nil)
        let orphan = #"{"format":"kanban","version":1,"name":"x","columns":[{"id":"a","name":"A","color":"red"}],"cards":[{"title":"t","status":"gone"}]}"#
        #expect(BoardIO.decode(Data(orphan.utf8))?.cards.first?.status == "a")
    }
}
