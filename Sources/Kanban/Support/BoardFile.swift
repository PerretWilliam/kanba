import AppKit
import UniformTypeIdentifiers

/// Portable JSON format for one board: `{"format":"kanban","version":1,"name":…,"columns":[…],"cards":[…]}`.
struct BoardFile: Codable {
    var format = "kanban"
    var version = 1
    var name: String
    var columns: [Column]
    var cards: [Card]
}

enum BoardIO {
    private static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }

    enum Format: String, CaseIterable {
        case json, csv, markdown
        var ext: String { self == .markdown ? "md" : rawValue }
        var label: String { ["JSON", "CSV", "Markdown"][Self.allCases.firstIndex(of: self)!] }
    }

    static func export(_ board: Board, as format: Format = .json) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.ext) ?? .plainText]
        panel.nameFieldStringValue = "\(board.name).\(format.ext)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data: Data
            switch format {
            case .json: data = try encoder.encode(BoardFile(name: board.name, columns: board.columns, cards: board.cards))
            case .csv: data = Data(csv(board).utf8)
            case .markdown: data = Data(markdown(board).utf8)
            }
            try data.write(to: url, options: .atomic)
        } catch { alert("Export impossible", error.localizedDescription) }
    }

    private static func day(_ d: Date?) -> String { d.map { $0.formatted(.iso8601.year().month().day()) } ?? "" }

    /// One row per card; UTF-8 with BOM so Excel reads accents correctly.
    static func csv(_ b: Board) -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let name = Dictionary(uniqueKeysWithValues: b.columns.map { ($0.id, $0.name) })
        var rows = ["Colonne,Titre,Notes,Priorité,Échéance,Tags"]
        for col in b.columns { for c in b.cards where c.status == col.id {
            rows.append([name[c.status] ?? "", c.title, c.notes, c.priority.label, day(c.due), c.tags.joined(separator: ", ")].map(q).joined(separator: ","))
        } }
        return "\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n"
    }

    static func markdown(_ b: Board) -> String {
        var out = "# \(b.name)\n"
        for col in b.columns {
            out += "\n## \(col.name)\n\n"
            for c in b.cards where c.status == col.id {
                let meta: [String?] = ["Priorité : \(c.priority.label)", c.due.map { "échéance \(day($0))" }, c.tags.isEmpty ? nil : c.tags.map { "#\($0)" }.joined(separator: " ")]
                out += "- [\(col.id == b.columns.last?.id ? "x" : " ")] **\(c.title)** — \(meta.compactMap { $0 }.joined(separator: " · "))\n"
                for l in c.notes.split(separator: "\n", omittingEmptySubsequences: true) { out += "  \(l)\n" }
            }
        }
        return out
    }

    /// Asks for a file and returns the board it contains (fresh board id; orphan cards go to the first column).
    static func importBoard() -> Board? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let f = try? d.decode(BoardFile.self, from: data),
              f.format == "kanban", !f.columns.isEmpty else {
            alert("Fichier invalide", "Ce fichier n'est pas un tableau Kanban au format JSON."); return nil
        }
        var cards = f.cards
        let ids = Set(f.columns.map(\.id))
        for i in cards.indices where !ids.contains(cards[i].status) { cards[i].status = f.columns[0].id }
        return Board(name: f.name, columns: f.columns, cards: cards)
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}
