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

    static func export(_ board: Board) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(board.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try encoder.encode(BoardFile(name: board.name, columns: board.columns, cards: board.cards)).write(to: url, options: .atomic) }
        catch { alert("Export impossible", error.localizedDescription) }
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
