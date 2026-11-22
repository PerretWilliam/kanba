import Foundation

/// Portable JSON format for one board: `{"format":"kanban","version":1,"name":…,"columns":[…],"cards":[…]}`.
struct BoardFile: Codable {
    var format = "kanban"
    var version = 1
    var name: String
    var columns: [Column]
    var cards: [Card]
}

enum BoardIO {
    static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }

    enum Format: String, CaseIterable {
        case json, csv, markdown
        var ext: String { self == .markdown ? "md" : rawValue }
        var label: String { ["JSON", "CSV", "Markdown"][Self.allCases.firstIndex(of: self)!] }
    }

    static func day(_ d: Date?) -> String { d.map { $0.formatted(.iso8601.year().month().day()) } ?? "" }

    /// One row per card; UTF-8 with BOM so Excel reads accents correctly.
    static func csv(_ b: Board) -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let name = Dictionary(uniqueKeysWithValues: b.columns.map { ($0.id, $0.name) })
        var rows = ["Colonne,Titre,Notes,Priorité,Échéance,Tags,Agents"]
        for col in b.columns { for c in b.cards where c.status == col.id {
            rows.append([name[c.status] ?? "", c.title, c.notes, c.priority.label, day(c.due), c.tags.joined(separator: ", "), c.agents.map(\.summary).joined(separator: "; ")].map(q).joined(separator: ","))
        } }
        return "\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n"
    }

    static func markdown(_ b: Board) -> String {
        var out = "# \(b.name)\n"
        for col in b.columns {
            out += "\n## \(col.name)\n\n"
            for c in b.cards where c.status == col.id {
                let meta: [String?] = ["Priorité : \(c.priority.label)", c.due.map { "échéance \(day($0))" }, c.tags.isEmpty ? nil : c.tags.map { "#\($0)" }.joined(separator: " "), c.agents.isEmpty ? nil : "agents : " + c.agents.map(\.summary).joined(separator: ", ")]
                out += "- [\(col.id == b.columns.last?.id ? "x" : " ")] **\(c.title)** — \(meta.compactMap { $0 }.joined(separator: " · "))\n"
                for l in c.notes.split(separator: "\n", omittingEmptySubsequences: true) { out += "  \(l)\n" }
            }
        }
        return out
    }

    /// File contents for a board in the given format.
    static func data(_ b: Board, as format: Format) throws -> Data {
        switch format {
        case .json: try encoder.encode(BoardFile(name: b.name, columns: b.columns, cards: b.cards))
        case .csv: Data(csv(b).utf8)
        case .markdown: Data(markdown(b).utf8)
        }
    }

    /// The board in a JSON share file (fresh board id; orphan cards go to the first column), nil if it is not one.
    static func decode(_ data: Data) -> Board? {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let f = try? d.decode(BoardFile.self, from: data), f.format == "kanban", !f.columns.isEmpty else { return nil }
        var cards = f.cards
        let ids = Set(f.columns.map(\.id))
        for i in cards.indices where !ids.contains(cards[i].status) { cards[i].status = f.columns[0].id }
        return Board(name: f.name, columns: f.columns, cards: cards)
    }
}
