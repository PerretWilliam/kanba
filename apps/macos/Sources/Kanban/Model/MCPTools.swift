import Foundation

struct MCPError: Error { let message: String; init(_ m: String) { message = m } }

/// What the MCP tools work on: a copy of the boards (the pending proposal if there is one, else the real ones).
/// Tools never touch the app directly; `Store.propose` turns the difference into a diff the user approves.
struct Workspace {
    var boards: [Board]
    var selected: UUID
    var filter: ViewFilter?     // set_filter: shown at once, not part of the data
    var select: UUID?           // select_board: switches the tab at once

    // MARK: lookups (a reference is a name or an id, case-insensitive)

    private func same(_ ref: String, _ vals: String...) -> Bool { vals.contains { ref.caseInsensitiveCompare($0) == .orderedSame } }

    /// The board named by `ref`, or the tab on screen (the first board if the selection is stale).
    func boardIndex(_ ref: String?) throws -> Int {
        if let ref {
            guard let i = boards.firstIndex(where: { same(ref, $0.id.uuidString, $0.name) }) else {
                throw MCPError("board not found: \(ref) (have: \(boards.map(\.name)))")
            }
            return i
        }
        guard !boards.isEmpty else { throw MCPError("there are no boards: create one with add_board") }
        return boards.firstIndex { $0.id == selected } ?? 0
    }
    func colIndex(_ b: Board, _ ref: String) throws -> Int {
        guard let i = b.columns.firstIndex(where: { same(ref, $0.id, $0.name) }) else { throw MCPError("column not found: \(ref) (have: \(b.columns.map(\.name)))") }
        return i
    }
    func findCard(_ ref: String) throws -> (board: Int, card: Int) {
        for (bi, b) in boards.enumerated() { if let ci = b.cards.firstIndex(where: { same(ref, $0.id.uuidString) }) { return (bi, ci) } }
        throw MCPError("card not found: \(ref)")
    }

    // MARK: parsing arguments

    static func date(_ s: String) throws -> Date? {
        if s.isEmpty { return nil }
        let f = ISO8601DateFormatter()
        for o: ISO8601DateFormatter.Options in [.withInternetDateTime, [.withInternetDateTime, .withFractionalSeconds], .withFullDate, [.withFullDate, .withTime, .withColonSeparatorInTime]] {
            f.formatOptions = o
            if let d = f.date(from: s) { return d }
        }
        throw MCPError("invalid date: \(s) (use ISO 8601, e.g. 2026-12-31)")
    }
    static func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    static func agent(_ x: Any) throws -> Agent {
        if let s = x as? String { return Agent(name: s) }
        guard let d = x as? [String: Any], let n = d["name"] as? String, !n.isEmpty else { throw MCPError("an agent needs a name (e.g. claude, codex, gemini, me)") }
        return Agent(name: n, model: d["model"] as? String ?? "", effort: d["effort"] as? String ?? "")
    }
    static func color(_ s: String) throws -> ColumnColor {
        guard let c = ColumnColor(rawValue: s) else { throw MCPError("color must be one of \(ColumnColor.allCases.map(\.rawValue))") }
        return c
    }
    static func orNull(_ s: String?) -> Any { s ?? NSNull() }
    static func priority(_ s: String) throws -> Priority {
        guard let p = ["low": Priority.low, "medium": .medium, "high": .high][s] else { throw MCPError("priority must be low, medium or high") }
        return p
    }

    /// Sets the fields present in `a` (absent = unchanged); `column` is looked up in `b`.
    func apply(_ c: inout Card, _ a: [String: Any], _ b: Board) throws {
        if let l = a["agents"] as? [Any] { c.agents = try l.map(Self.agent) }
        if let v = a["title"] as? String { c.title = v }
        if let v = a["notes"] as? String { c.notes = v }
        if let v = a["priority"] as? String { c.priority = try Self.priority(v) }
        if let v = a["tags"] as? [String] { c.tags = v }
        if let v = a["due"] as? String { c.due = try Self.date(v) }
        if let v = a["column"] as? String { c.status = b.columns[try colIndex(b, v)].id }
    }

    func makeCard(_ a: [String: Any], _ b: Board) throws -> Card {
        var c = Card(status: b.columns[0].id)
        try apply(&c, a, b)
        return c
    }

    /// Card order = array order: puts card `id` at 1-based position `pos` among the cards of its column.
    static func place(_ b: inout Board, _ id: UUID, _ pos: Int) {
        guard let from = b.cards.firstIndex(where: { $0.id == id }) else { return }
        let c = b.cards.remove(at: from)
        let col = b.cards.indices.filter { b.cards[$0].status == c.status }
        let at = col.isEmpty ? b.cards.count : pos <= col.count ? col[max(pos, 1) - 1] : col.last! + 1
        b.cards.insert(c, at: at)
    }

    // MARK: output

    static func json(_ o: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

/// The MCP tools. `call` runs one on a workspace and returns the text sent back to the AI client.
extension Workspace {
    static let readOnly: Set = ["get_boards", "select_board", "set_filter", "export_board"]

    mutating func call(_ name: String, _ a: [String: Any]) throws -> String {
        let board = a["board"] as? String
        switch name {
        case "get_boards": return try getBoards(a)
        case "add_cards", "update_cards":   // batch: each item takes the single tool's arguments (top-level ones like `board` are defaults); all or nothing
            let one = String(name.dropLast()), base = a.filter { $0.key != "cards" }
            let r = try (a["cards"] as? [[String: Any]] ?? []).map { try call(one, base.merging($0) { $1 }) }
            return one == "add_card" ? "[" + r.joined(separator: ",") + "]" : "\(r.count) cards updated"   // add: [{"id":…},…]
        case "add_card":
            let bi = try boardIndex(board), c = try makeCard(a, boards[bi])
            boards[bi].cards.append(c)
            if let p = a["position"] as? Int { Self.place(&boards[bi], c.id, p) }
            return Self.json(["id": c.id.uuidString])
        case "update_card":
            var (bi, ci) = try findCard(a["card_id"] as? String ?? "")
            var c = boards[bi].cards[ci]
            if let to = a["to_board"] as? String {   // another board: same-named column if any, else the first; `column` overrides
                let t = try boardIndex(to)
                if t != bi {
                    let old = boards[bi].columns.first { $0.id == c.status }?.name ?? ""
                    boards[bi].cards.remove(at: ci)
                    c.status = (boards[t].columns.first { $0.name.lowercased() == old.lowercased() } ?? boards[t].columns[0]).id
                    boards[t].cards.append(c); bi = t; ci = boards[t].cards.count - 1
                }
            }
            try apply(&c, a, boards[bi])
            boards[bi].cards[ci] = c
            if let p = a["position"] as? Int { Self.place(&boards[bi], c.id, p) }
            return "ok"
        case "reorder_cards":   // card_ids first, in that order, at the top of the column; the others keep their order after them
            let bi = try boardIndex(board), col = boards[bi].columns[try colIndex(boards[bi], a["column"] as? String ?? "")].id
            let ids = try (a["card_ids"] as? [String] ?? []).map { ref -> UUID in
                let (b, c) = try findCard(ref); return boards[b].cards[c].id
            }
            let listed = ids.compactMap { id in boards[bi].cards.first { $0.id == id } }
            guard listed.allSatisfy({ $0.status == col }), Set(ids).count == ids.count, listed.count == ids.count else { throw MCPError("card_ids must be distinct cards of that column") }
            let slots = boards[bi].cards.indices.filter { boards[bi].cards[$0].status == col }
            let seq = listed + slots.map { boards[bi].cards[$0] }.filter { c in !ids.contains(c.id) }
            for (s, c) in zip(slots, seq) { boards[bi].cards[s] = c }
            return "ok"
        case "delete_card":
            let (bi, ci) = try findCard(a["card_id"] as? String ?? "")
            boards[bi].cards.remove(at: ci); return "ok"
        case "clear_last_column":   // the app's trash button
            let bi = try boardIndex(board), last = boards[bi].columns.last!.id, n = boards[bi].cards.count
            boards[bi].cards.removeAll { $0.status == last }
            return "\(n - boards[bi].cards.count) cards deleted"
        case "add_column":
            let bi = try boardIndex(board)
            let color = try (a["color"] as? String).map(Self.color) ?? .gray
            let col = Column(name: a["name"] as? String ?? "", color: color)
            boards[bi].columns.append(col); return Self.json(["id": col.id])
        case "update_column":
            let bi = try boardIndex(board), ci = try colIndex(boards[bi], a["column"] as? String ?? "")
            if let n = a["name"] as? String { boards[bi].columns[ci].name = n }
            if let c = a["color"] as? String { boards[bi].columns[ci].color = try Self.color(c) }
            return "ok"
        case "delete_column":   // same rule as the app: its cards go to the left neighbour (or the new first column)
            let bi = try boardIndex(board), ci = try colIndex(boards[bi], a["column"] as? String ?? "")
            guard boards[bi].columns.count > 1 else { throw MCPError("cannot delete the last column") }
            let id = boards[bi].columns[ci].id, target = boards[bi].columns[ci == 0 ? 1 : ci - 1].id
            for k in boards[bi].cards.indices where boards[bi].cards[k].status == id { boards[bi].cards[k].status = target }
            boards[bi].columns.remove(at: ci); return "ok"
        case "add_board": return try addBoard(a)
        case "update_board":   // closed=true hides the tab (still listed in the Projets menu); false reopens it
            let bi = try boardIndex(a["board"] as? String ?? "")
            if let n = a["name"] as? String { boards[bi].name = n }
            if let c = a["closed"] as? Bool { boards[bi].closed = c ? true : nil }
            return "ok"
        case "select_board":   // UI state, not data: applied at once
            select = boards[try boardIndex(a["board"] as? String ?? "")].id; return "ok"
        case "set_filter":     // screen state, not data; no argument clears it
            var f = ViewFilter()
            if let p = a["priority"] as? String { f.priority = try Self.priority(p) }
            if let t = a["tag"] as? String, !t.isEmpty { f.tag = t }
            if let g = a["agent"] as? String, !g.isEmpty { f.agent = g }
            f.query = a["query"] as? String ?? ""
            filter = f
            var out: [String: Any] = [:]
            if f.priority != nil { out["priority"] = a["priority"] }
            if let t = f.tag { out["tag"] = t }
            if let g = f.agent { out["agent"] = g }
            if !f.query.isEmpty { out["query"] = f.query }
            return Self.json(["filter": out])
        case "delete_board":
            let id = boards[try boardIndex(a["board"] as? String ?? "")].id
            boards.removeAll { $0.id == id || $0.parent == id }   // a board takes its phases with it
            return "ok"
        case "export_board": return try export(a)
        case "import_board": return try importBoard(a)
        default: throw MCPError("unknown tool: \(name)")
        }
    }

    // MARK: bigger tools

    private func getBoards(_ a: [String: Any]) throws -> String {
        let q = (a["query"] as? String ?? "").lowercased(), prio = try (a["priority"] as? String).map(Self.priority)
        let tag = a["tag"] as? String, agent = (a["agent"] as? String)?.lowercased()
        func keep(_ c: Card) -> Bool {
            (q.isEmpty || ([c.title, c.notes] + c.tags).joined(separator: " ").lowercased().contains(q))
                && (prio == nil || c.priority == prio) && (tag == nil || c.tags.contains(tag!))
                && (agent == nil || c.agents.contains { ($0.name + " " + $0.model).lowercased().contains(agent!) })
        }
        let list = try (a["board"] as? String).map { [boards[try boardIndex($0)]] } ?? boards
        let withNotes = a["board"] != nil   // all boards at once would be huge: notes only when one board is asked for
        let out: [[String: Any]] = list.map { b in
            ["id": b.id.uuidString, "name": b.name, "parent": Self.orNull(b.parent?.uuidString), "closed": b.closed == true,
             "columns": b.columns.map { ["id": $0.id, "name": $0.name, "color": $0.color.rawValue] },
             "done_column": b.columns.last?.name ?? "",
             "cards": b.cards.enumerated().filter { keep($0.element) }.map { i, c in
                 ["position": 1 + b.cards[..<i].filter { $0.status == c.status }.count, "id": c.id.uuidString, "title": c.title,
                  "column": Self.orNull(b.columns.first { $0.id == c.status }?.name),
                  "priority": ["low", "medium", "high"][c.priority.rawValue], "tags": c.tags, "notes": withNotes ? c.notes : "",
                  "agents": c.agents.map { ["name": $0.name, "model": $0.model, "effort": $0.effort] },
                  "due": Self.orNull(c.due.map(Self.iso))] as [String: Any] }]
        }
        let sel: Any = boards.isEmpty ? NSNull() : boards[(try? boardIndex(nil)) ?? 0].id.uuidString
        return Self.json(["selected": sel, "boards": out])
    }

    private mutating func addBoard(_ a: [String: Any]) throws -> String {
        let parent = try (a["parent"] as? String).map { boards[try boardIndex($0)] }
        if parent?.parent != nil { throw MCPError("phases cannot have phases: pass the top-level board") }
        var b = Board(name: a["name"] as? String ?? "")
        if let names = a["columns"] as? [String], !names.isEmpty {
            b.columns = names.enumerated().map { Column(name: $1, color: ColumnColor.allCases[$0 % ColumnColor.allCases.count]) }
        } else if let parent { b.columns = parent.columns }
        b.parent = parent?.id
        b.cards = try (a["cards"] as? [[String: Any]] ?? []).map { try makeCard($0, b) }
        boards.append(b)
        return Self.json(["id": b.id.uuidString])
    }

    private func export(_ a: [String: Any]) throws -> String {
        let b = boards[try boardIndex(a["board"] as? String)], path = NSString(string: a["path"] as? String ?? "").expandingTildeInPath
        guard let f = BoardIO.Format(rawValue: a["format"] as? String ?? "json") else { throw MCPError("format must be json, csv or markdown") }
        if FileManager.default.fileExists(atPath: path), a["overwrite"] as? Bool != true { throw MCPError("\(path) exists (pass overwrite=true)") }
        try BoardIO.data(b, as: f).write(to: URL(fileURLWithPath: path), options: .atomic)
        return path
    }

    private mutating func importBoard(_ a: [String: Any]) throws -> String {
        let path = NSString(string: a["path"] as? String ?? "").expandingTildeInPath
        guard let d = FileManager.default.contents(atPath: path), var b = BoardIO.decode(d) else { throw MCPError("not a Kanban board file") }
        for i in b.cards.indices { b.cards[i].id = UUID() }   // fresh ids: the same file can be imported twice
        boards.append(b)
        return Self.json(["id": b.id.uuidString])
    }
}
