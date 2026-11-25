import Testing
import Foundation
@testable import Kanban

/// The MCP tools on a plain Workspace (no app, no disk but temp files).
struct MCPToolsTests {
    static func uid(_ n: Int) -> UUID { UUID(uuidString: "00000000-0000-0000-0000-" + String(format: "%012d", n))! }
    static let b1 = uid(101), b2 = uid(102)
    static func card(_ n: Int, _ title: String, _ status: String = "todo") -> Card { Card(id: uid(n), title: title, status: status) }

    func make() -> Workspace {
        var three = Self.card(3, "three", "doing")
        three.priority = .high; three.tags = ["x"]; three.notes = "Hello"; three.due = Date(timeIntervalSinceReferenceDate: 86400)
        three.agents = [Agent(name: "claude", model: "Opus 5.5", effort: "high")]
        let main = Board(id: Self.b1, name: "Main", cards: [Self.card(1, "one"), Self.card(2, "two"), three, Self.card(4, "four", "done")])
        let other = Board(id: Self.b2, name: "Other", columns: [Column(id: "a", name: "En cours", color: .red), Column(id: "b", name: "Z", color: .pink)])
        return Workspace(boards: [main, other], selected: Self.b1)
    }
    func run(_ w: inout Workspace, _ tool: String, _ a: [String: Any] = [:]) throws -> String { try w.call(tool, a) }
    func titles(_ w: Workspace, _ i: Int = 0) -> [String] { w.boards[i].cards.map(\.title) }
    func obj(_ s: String) throws -> [String: Any] { try #require(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]) }
    func fails(_ w: inout Workspace, _ tool: String, _ a: [String: Any] = [:], _ text: String) {
        do { _ = try w.call(tool, a); Issue.record("\(tool) should have failed") }
        catch let e as MCPError { #expect(e.message.contains(text), "\(e.message)") }
        catch { Issue.record("\(error)") }
    }

    @Test func lookups() throws {
        var w = make()
        #expect(try w.boardIndex(nil) == 0 && w.boardIndex("other") == 1 && w.boardIndex(Self.b2.uuidString.lowercased()) == 1)
        w.selected = UUID(); #expect(try w.boardIndex(nil) == 0)   // stale selection: first board
        #expect(try w.colIndex(w.boards[0], "EN COURS") == 1 && w.findCard(Self.uid(2).uuidString.lowercased()) == (0, 1))
        fails(&w, "get_boards", ["board": "nope"], "board not found")
        fails(&w, "update_column", ["column": "nope"], "column not found")
        fails(&w, "delete_card", ["card_id": "nope"], "card not found")
        fails(&w, "bogus", [:], "unknown tool")
        w.boards = []
        fails(&w, "add_card", ["title": "x"], "no boards")
        #expect(try obj(run(&w, "get_boards")).keys.contains("selected"))
    }

    @Test func parsing() throws {
        #expect(try Workspace.date("") == nil)
        #expect(try Workspace.date("2001-01-02") == Date(timeIntervalSinceReferenceDate: 86400))
        #expect(try Workspace.date("2001-01-02T00:00:00Z") == Date(timeIntervalSinceReferenceDate: 86400))
        #expect(try Workspace.date("2001-01-02T00:00:00.5Z") != nil && Workspace.date("2001-01-02T01:00:00+01:00") == Date(timeIntervalSinceReferenceDate: 86400))
        #expect(try Workspace.date("2001-01-02T00:00:00") == Date(timeIntervalSinceReferenceDate: 86400))
        #expect(Workspace.iso(Date(timeIntervalSinceReferenceDate: 86400)) == "2001-01-02T00:00:00Z")
        #expect(throws: MCPError.self) { try Workspace.date("tomorrow") }
        #expect(try Workspace.agent("me") == Agent(name: "me"))
        #expect(try Workspace.agent(["name": "codex", "model": "GPT-5", "effort": "max"]) == Agent(name: "codex", model: "GPT-5", effort: "max"))
        #expect(throws: MCPError.self) { try Workspace.agent(["model": "x"]) }
        #expect(throws: MCPError.self) { try Workspace.priority("urgent") }
        #expect(throws: MCPError.self) { try Workspace.color("mauve") }
    }

    @Test func getBoardsAndFilters() throws {
        var w = make()
        w.boards[0].cards.append(Self.card(9, "orphan", "gone"))
        let out = try obj(run(&w, "get_boards"))
        #expect(out["selected"] as? String == Self.b1.uuidString)
        let boards = try #require(out["boards"] as? [[String: Any]])
        #expect(boards.count == 2 && boards[0]["done_column"] as? String == "Terminé" && boards[0]["closed"] as? Bool == false && boards[0]["parent"] is NSNull)
        let cards = try #require(boards[0]["cards"] as? [[String: Any]])
        let c3 = try #require(cards.first { $0["title"] as? String == "three" })
        #expect(c3["position"] as? Int == 1 && c3["column"] as? String == "En cours" && c3["priority"] as? String == "high" && c3["due"] as? String == "2001-01-02T00:00:00Z")
        #expect((c3["agents"] as? [[String: Any]])?.first?["model"] as? String == "Opus 5.5")
        #expect(cards.first { $0["title"] as? String == "two" }?["position"] as? Int == 2)
        #expect(cards.first { $0["title"] as? String == "orphan" }?["column"] is NSNull)
        #expect(cards.allSatisfy { $0["notes"] as? String == "" })   // no notes when listing every board
        func ids(_ a: [String: Any]) throws -> [String] {
            let o = try obj(run(&w, "get_boards", ["board": "Main"].merging(a) { $1 }))
            return ((o["boards"] as? [[String: Any]])?[0]["cards"] as? [[String: Any]] ?? []).compactMap { $0["title"] as? String }
        }
        #expect(try ids(["query": "hello"]) == ["three"] && ids(["priority": "high"]) == ["three"] && ids(["tag": "x"]) == ["three"])
        #expect(try ids(["agent": "opus"]) == ["three"] && ids(["agent": "gemini"]) == [] && ids([:]).count == 5)
        w.boards[1].parent = Self.b1; w.boards[1].closed = true
        let again = try obj(run(&w, "get_boards", ["board": "Other"]))
        let o = try #require((again["boards"] as? [[String: Any]])?.first)
        #expect(o["parent"] as? String == Self.b1.uuidString && o["closed"] as? Bool == true)
    }

    @Test func addCard() throws {
        var w = make()
        let r = try obj(run(&w, "add_card", ["title": "new", "notes": "# md", "priority": "high", "tags": ["t"], "due": "2001-01-02", "column": "doing",
                                             "agents": ["me", ["name": "claude", "model": "Opus 5.5", "effort": "high"]], "position": 1]))
        let c = try #require(w.boards[0].cards.first { $0.id.uuidString == r["id"] as? String })
        #expect(c.priority == .high && c.tags == ["t"] && c.due == Date(timeIntervalSinceReferenceDate: 86400) && c.status == "doing" && c.agents.count == 2)
        #expect(titles(w) == ["one", "two", "new", "three", "four"])   // position 1 of "doing" = before "three"
        _ = try run(&w, "add_card", ["title": "other", "board": "Other"]); #expect(w.boards[1].cards[0].status == "a")
        _ = try run(&w, "add_card", ["title": "z", "column": "done", "position": 9]); #expect(titles(w).last == "z")
        _ = try run(&w, "add_card", ["title": "e", "board": "Other", "column": "Z", "position": 1]); #expect(w.boards[1].cards.last?.title == "e")   // empty column
        fails(&w, "add_card", ["title": "x", "priority": "urgent"], "priority")
    }

    @Test func updateCard() throws {
        var w = make()
        let id = Self.uid(1).uuidString
        _ = try run(&w, "update_card", ["card_id": id, "title": "uno", "notes": "n", "priority": "low", "tags": ["a"], "due": "2001-01-02", "column": "doing", "agents": [Any]()])
        let c = w.boards[0].cards[0]
        #expect(c.title == "uno" && c.priority == .low && c.status == "doing" && c.due != nil && c.agents.isEmpty)
        _ = try run(&w, "update_card", ["card_id": id, "due": ""]); #expect(w.boards[0].cards[0].due == nil)
        _ = try run(&w, "update_card", ["card_id": Self.uid(3).uuidString, "position": 1]); #expect(titles(w).prefix(2) == ["three", "uno"])
        _ = try run(&w, "update_card", ["card_id": Self.uid(2).uuidString, "to_board": "main"]); #expect(w.boards[0].cards.count == 4)   // same board: nothing moves
        _ = try run(&w, "update_card", ["card_id": Self.uid(3).uuidString, "to_board": "Other"])   // "En cours" exists there
        #expect(titles(w, 1) == ["three"] && w.boards[1].cards[0].status == "a")
        _ = try run(&w, "update_card", ["card_id": id, "to_board": "Other", "column": "Z"]); #expect(w.boards[1].cards.last?.status == "b")
        _ = try run(&w, "update_card", ["card_id": Self.uid(4).uuidString, "to_board": "Other"])   // "Terminé" does not exist there: first column
        #expect(w.boards[1].cards.last?.status == "a" && w.boards[0].cards.map(\.title) == ["two"])
        fails(&w, "update_card", ["card_id": Self.uid(2).uuidString, "agents": [["model": "x"]]], "needs a name")
    }

    @Test func reorderDeleteClear() throws {
        var w = make()
        _ = try run(&w, "reorder_cards", ["column": "todo", "card_ids": [Self.uid(2).uuidString]]); #expect(titles(w).prefix(2) == ["two", "one"])
        _ = try run(&w, "reorder_cards", ["column": "todo", "card_ids": [Self.uid(1).uuidString, Self.uid(2).uuidString]]); #expect(titles(w).prefix(2) == ["one", "two"])
        fails(&w, "reorder_cards", ["column": "todo", "card_ids": [Self.uid(3).uuidString]], "distinct cards of that column")
        fails(&w, "reorder_cards", ["column": "todo", "card_ids": [Self.uid(1).uuidString, Self.uid(1).uuidString]], "distinct")
        fails(&w, "reorder_cards", ["column": "todo", "card_ids": ["nope"]], "card not found")
        _ = try run(&w, "delete_card", ["card_id": Self.uid(1).uuidString]); #expect(!titles(w).contains("one"))
        #expect(try run(&w, "clear_last_column") == "1 cards deleted" && !titles(w).contains("four"))
    }

    @Test func columns() throws {
        var w = make()
        let id = try #require(try obj(run(&w, "add_column", ["name": "Review", "color": "red"]))["id"] as? String)
        #expect(w.boards[0].columns.last?.color == .red)
        _ = try run(&w, "add_column", ["name": "Plain", "board": "Other"]); #expect(w.boards[1].columns.last?.color == .gray)
        _ = try run(&w, "update_column", ["column": id, "name": "QA"]); _ = try run(&w, "update_column", ["column": "QA", "color": "teal"]); _ = try run(&w, "update_column", ["column": "QA"])
        #expect(w.boards[0].columns.last?.name == "QA" && w.boards[0].columns.last?.color == .teal)
        _ = try run(&w, "delete_column", ["column": "QA"]); #expect(w.boards[0].columns.count == 3)
        _ = try run(&w, "delete_column", ["column": "todo"])   // first column: its cards go to the next one
        #expect(Set(w.boards[0].cards.map(\.status)) == ["doing", "done"])
        w.boards[1].columns = [w.boards[1].columns[0]]
        fails(&w, "delete_column", ["column": "a", "board": "Other"], "last column")
        fails(&w, "add_column", ["name": "x", "color": "mauve"], "color")
        fails(&w, "update_column", ["column": "done", "color": "mauve"], "color")
    }

    @Test func boards() throws {
        var w = make()
        let r = try obj(run(&w, "add_board", ["name": "T"])); let t = try #require(w.boards.last)
        #expect(t.id.uuidString == r["id"] as? String && t.columns == Board.defaultColumns && t.cards.isEmpty && t.parent == nil)
        _ = try run(&w, "add_board", ["name": "C", "columns": ["A", "B", "C", "D", "E", "F", "G", "H", "I"], "cards": [["title": "x", "column": "B", "agents": ["me"]]]])
        let c = try #require(w.boards.last)
        #expect(c.columns.count == 9 && c.columns[8].color == .gray && c.cards[0].status == c.columns[1].id)
        _ = try run(&w, "add_board", ["name": "Phase", "parent": "Main"]); let p = try #require(w.boards.last)
        #expect(p.parent == Self.b1 && p.columns.map(\.id) == ["todo", "doing", "done"])
        fails(&w, "add_board", ["name": "Sub", "parent": "Phase"], "phases cannot have phases")
        _ = try run(&w, "add_board", ["name": "Own", "parent": "Main", "columns": ["Only"]]); #expect(w.boards.last?.columns.count == 1)

        _ = try run(&w, "update_board", ["board": "Other", "name": "Renamed", "closed": true]); #expect(w.boards[1].name == "Renamed" && w.boards[1].closed == true)
        _ = try run(&w, "update_board", ["board": "Renamed", "closed": false]); #expect(w.boards[1].closed == nil)
        _ = try run(&w, "update_board", ["board": "Renamed"])
        _ = try run(&w, "delete_board", ["board": "Main"])   // takes its phases with it
        #expect(w.boards.map(\.name) == ["Renamed", "T", "C"])
    }

    @Test func selectAndFilter() throws {
        var w = make()
        _ = try run(&w, "select_board", ["board": "Other"]); #expect(w.select == Self.b2)
        _ = try run(&w, "set_filter", ["priority": "high", "tag": "ops", "agent": "claude", "query": "x"])
        #expect(w.filter == ViewFilter(priority: .high, tag: "ops", agent: "claude", query: "x"))
        let r = try obj(run(&w, "set_filter", ["tag": ""]))   // empty = clears the screen filter
        #expect(w.filter?.isEmpty == true && (r["filter"] as? [String: Any])?.isEmpty == true)
        fails(&w, "set_filter", ["priority": "urgent"], "priority")
    }

    @Test func exportAndImport() throws {
        var w = make()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kanba-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = dir.appendingPathComponent("x.json").path
        #expect(try run(&w, "export_board", ["path": json]) == json)
        fails(&w, "export_board", ["path": json], "exists")
        _ = try run(&w, "export_board", ["path": json, "overwrite": true])
        let csv = dir.appendingPathComponent("x.csv").path, md = dir.appendingPathComponent("x.md").path
        _ = try run(&w, "export_board", ["path": csv, "format": "csv"]); _ = try run(&w, "export_board", ["path": md, "format": "markdown", "board": "Main"])
        #expect(try String(contentsOfFile: csv, encoding: .utf8).contains("three"))
        #expect(try String(contentsOfFile: md, encoding: .utf8).contains("- [x] **four**"))
        fails(&w, "export_board", ["path": dir.appendingPathComponent("x.bin").path, "format": "pdf"], "format must be")

        let r = try obj(run(&w, "import_board", ["path": json]))
        let b = try #require(w.boards.last)
        #expect(b.id.uuidString == r["id"] as? String && b.cards.count == 4 && b.cards[0].id != Self.uid(1) && b.cards[2].due == Date(timeIntervalSinceReferenceDate: 86400))
        _ = try run(&w, "import_board", ["path": json]); #expect(w.boards.count == 4)   // twice: no id collision
        try Data("nope".utf8).write(to: dir.appendingPathComponent("bad.json"))
        fails(&w, "import_board", ["path": dir.appendingPathComponent("bad.json").path], "not a Kanban board file")
        fails(&w, "import_board", ["path": dir.appendingPathComponent("missing.json").path], "not a Kanban board file")
    }
}
