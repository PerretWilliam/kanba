import SwiftUI

enum ColumnColor: String, Codable, CaseIterable, Identifiable {
    case gray, blue, green, orange, purple, pink, teal, red
    var id: Self { self }
    var color: Color {
        switch self {
        case .gray: .gray; case .blue: .blue; case .green: .green; case .orange: .orange
        case .purple: .purple; case .pink: .pink; case .teal: .teal; case .red: .red
        }
    }
    var label: String {
        ["gray": "Gris", "blue": "Bleu", "green": "Vert", "orange": "Orange",
         "purple": "Violet", "pink": "Rose", "teal": "Turquoise", "red": "Rouge"][rawValue]!
    }
}

struct Column: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var name: String
    var color: ColumnColor
}

/// One tab: its own columns and cards. A card's `status` is the id of its column.
/// By convention the last column is the "done" one (dimmed cards, emptied by the trash button).
struct Board: Identifiable, Codable {
    var id = UUID()
    var name: String
    var columns = Board.defaultColumns
    var cards: [Card] = []
    var parent: UUID?   // set = a phase (sub-board) of that board; its own columns and cards

    // Fixed ids so cards saved before columns became dynamic ("todo"/"doing"/"done") still match.
    static let defaultColumns = [Column(id: "todo", name: "À faire", color: .gray),
                                 Column(id: "doing", name: "En cours", color: .blue),
                                 Column(id: "done", name: "Terminé", color: .green)]
}

enum Priority: Int, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: Int { rawValue }
    var label: String { ["Basse", "Moyenne", "Haute"][rawValue] }
    var color: Color { [Color.green, .orange, .red][rawValue] }
}

struct Card: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var notes = ""
    var priority = Priority.medium
    var due: Date?
    var status = ""
    var tags: [String] = []
}

// Tolerant decoding so cards saved before a field existed still load.
extension Card {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .medium
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}
