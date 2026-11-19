import SwiftUI

/// Changes an AI client wants to make, written to proposal.json by the MCP server instead of touching boards.json.
/// `base` is what the boards looked like when the first change was proposed, `boards` the proposed result.
struct Proposal: Codable {
    var actor: String
    var base: [Board]
    var boards: [Board]
}

/// One reviewable line of the diff (a card, a column or a board), with the code to apply it to the live boards.
struct Change: Identifiable {
    enum Kind { case add, remove, edit }
    struct Line { var label: String; var old: String?; var new: String? }
    let id = UUID()
    var kind: Kind
    var title: String
    var scope = ""                 // board name
    var lines: [Line] = []
    var addedBoard: UUID?          // set when the change creates a board (we switch to it)
    var apply: (inout [Board]) -> Void
}

extension Proposal {
    var changes: [Change] { Self.diff(base, boards) }

    /// Entity-level diff by id. Each change only touches what the AI touched, so edits the user made meanwhile survive.
    static func diff(_ base: [Board], _ new: [Board]) -> [Change] {
        var out: [Change] = []
        let old = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newIDs = Set(new.map(\.id))
        let date: (Date) -> String = { $0.formatted(.dateTime.day().month().year().locale(Locale(identifier: "fr_FR"))) }
        func onBoard(_ id: UUID, _ f: @escaping (inout Board) -> Void) -> (inout [Board]) -> Void {
            { b in if let i = b.firstIndex(where: { $0.id == id }) { f(&b[i]) } }
        }

        for nb in new {
            guard let ob = old[nb.id] else {
                out.append(Change(kind: .add, title: "Tableau « \(nb.name) »",
                                  lines: [.init(label: "Contenu", old: nil, new: "\(nb.columns.count) colonnes, \(nb.cards.count) cartes")],
                                  addedBoard: nb.id) { b in if !b.contains(where: { $0.id == nb.id }) { b.append(nb) } })
                continue
            }
            let scope = nb.name
            if ob.name != nb.name {
                out.append(Change(kind: .edit, title: "Tableau « \(ob.name) »", lines: [.init(label: "Nom", old: ob.name, new: nb.name)],
                                  apply: onBoard(nb.id) { $0.name = nb.name }))
            }

            // Columns
            for (i, c) in nb.columns.enumerated() {
                if let o = ob.columns.first(where: { $0.id == c.id }) {
                    guard o != c else { continue }
                    var l: [Change.Line] = []
                    if o.name != c.name { l.append(.init(label: "Nom", old: o.name, new: c.name)) }
                    if o.color != c.color { l.append(.init(label: "Couleur", old: o.color.label, new: c.color.label)) }
                    out.append(Change(kind: .edit, title: "Colonne « \(o.name) »", scope: scope, lines: l, apply: onBoard(nb.id) { b in
                        if let k = b.columns.firstIndex(where: { $0.id == c.id }) { b.columns[k].name = c.name; b.columns[k].color = c.color }
                    }))
                } else {
                    out.append(Change(kind: .add, title: "Colonne « \(c.name) »", scope: scope, lines: [.init(label: "Couleur", old: nil, new: c.color.label)],
                                      apply: onBoard(nb.id) { b in
                        if !b.columns.contains(where: { $0.id == c.id }) { b.columns.insert(c, at: min(i, b.columns.count)) }
                    }))
                }
            }
            for o in ob.columns where !nb.columns.contains(where: { $0.id == o.id }) {
                out.append(Change(kind: .remove, title: "Colonne « \(o.name) »", scope: scope, apply: onBoard(nb.id) { b in
                    guard b.columns.count > 1, let k = b.columns.firstIndex(where: { $0.id == o.id }) else { return }
                    let target = b.columns[k == 0 ? 1 : k - 1].id   // same rule as the app: cards fall back to the left neighbour
                    for j in b.cards.indices where b.cards[j].status == o.id { b.cards[j].status = target }
                    b.columns.remove(at: k)
                }))
            }

            // Cards
            let colName: (Board, String) -> String = { b, id in b.columns.first { $0.id == id }?.name ?? "?" }
            for c in nb.cards {
                if let o = ob.cards.first(where: { $0.id == c.id }) {
                    guard o != c else { continue }
                    var l: [Change.Line] = []
                    if o.title != c.title { l.append(.init(label: "Titre", old: o.title, new: c.title)) }
                    if o.status != c.status { l.append(.init(label: "Colonne", old: colName(ob, o.status), new: colName(nb, c.status))) }
                    if o.priority != c.priority { l.append(.init(label: "Priorité", old: o.priority.label, new: c.priority.label)) }
                    if o.due != c.due { l.append(.init(label: "Échéance", old: o.due.map(date), new: c.due.map(date) ?? "aucune")) }
                    if o.tags != c.tags { l.append(.init(label: "Tags", old: o.tags.joined(separator: ", "), new: c.tags.joined(separator: ", "))) }
                    if o.notes != c.notes { l.append(.init(label: "Notes", old: o.notes.isEmpty ? nil : o.notes, new: c.notes.isEmpty ? "(vide)" : c.notes)) }
                    out.append(Change(kind: .edit, title: "Carte « \(o.title) »", scope: scope, lines: l, apply: onBoard(nb.id) { b in
                        guard let k = b.cards.firstIndex(where: { $0.id == c.id }) else { return }
                        if o.title != c.title { b.cards[k].title = c.title }
                        if o.notes != c.notes { b.cards[k].notes = c.notes }
                        if o.priority != c.priority { b.cards[k].priority = c.priority }
                        if o.due != c.due { b.cards[k].due = c.due }
                        if o.tags != c.tags { b.cards[k].tags = c.tags }
                        if o.status != c.status { b.cards[k].status = b.columns.contains { $0.id == c.status } ? c.status : b.columns[0].id }
                    }))
                } else {
                    var l: [Change.Line] = [.init(label: "Colonne", old: nil, new: colName(nb, c.status)), .init(label: "Priorité", old: nil, new: c.priority.label)]
                    if let d = c.due { l.append(.init(label: "Échéance", old: nil, new: date(d))) }
                    if !c.tags.isEmpty { l.append(.init(label: "Tags", old: nil, new: c.tags.joined(separator: ", "))) }
                    if !c.notes.isEmpty { l.append(.init(label: "Notes", old: nil, new: c.notes)) }
                    out.append(Change(kind: .add, title: "Carte « \(c.title) »", scope: scope, lines: l, apply: onBoard(nb.id) { b in
                        guard !b.cards.contains(where: { $0.id == c.id }) else { return }
                        var card = c
                        if !b.columns.contains(where: { $0.id == c.status }) { card.status = b.columns[0].id }
                        b.cards.append(card)
                    }))
                }
            }
            for o in ob.cards where !nb.cards.contains(where: { $0.id == o.id }) {
                out.append(Change(kind: .remove, title: "Carte « \(o.title) »", scope: scope,
                                  lines: [.init(label: "Colonne", old: colName(ob, o.status), new: nil)],
                                  apply: onBoard(nb.id) { b in b.cards.removeAll { $0.id == o.id } }))
            }
        }
        for ob in base where !newIDs.contains(ob.id) {
            out.append(Change(kind: .remove, title: "Tableau « \(ob.name) »",
                              lines: [.init(label: "Contenu", old: "\(ob.columns.count) colonnes, \(ob.cards.count) cartes", new: nil)]) { b in
                if b.count > 1 { b.removeAll { $0.id == ob.id } }
            })
        }
        return out
    }
}
