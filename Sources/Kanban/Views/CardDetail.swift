import SwiftUI

/// Right-hand panel showing a card cleanly (notes rendered as markdown), with edit / delete.
struct CardDetail: View {
    let card: Card
    let column: Column?
    var isDone = false
    let onEdit: () -> Void, onDelete: () -> Void, onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Carte").font(.inter(12, .medium)).foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").padding(4).contentShape(.rect) }
                    .buttonStyle(.borderless).keyboardShortcut(.cancelAction).help("Fermer")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(card.title).font(.mono(17, .bold)).strikethrough(isDone).textSelection(.enabled)
                    HStack(spacing: 6) {
                        if let c = column { TagChip(tag: c.name, tint: c.color.color) }
                        TagChip(tag: card.priority.label, tint: card.priority.color)
                        if let due = card.due {
                            Label(due.formatted(.dateTime.day().month(.wide).year()), systemImage: "calendar")
                                .font(.inter(12)).foregroundStyle(!isDone && due < Calendar.current.startOfDay(for: .now) ? .red : .secondary)
                        }
                    }
                    if !card.agents.isEmpty {
                        section("Agents") {
                            ForEach(card.agents) { a in
                                HStack(spacing: 8) {
                                    AgentIcon(name: a.name).frame(width: 18, height: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(a.label).font(.inter(13, .medium))
                                        if !a.detail.isEmpty { Text(a.detail).font(.inter(11)).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                    }
                    if !card.tags.isEmpty { section("Tags") { FlowLayout(spacing: 4) { ForEach(card.tags, id: \.self) { TagChip(tag: $0) } } } }
                    if !card.notes.isEmpty { section("Notes") { MarkdownView(text: card.notes) } }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("Supprimer", role: .destructive, action: onDelete).buttonStyle(.glass).foregroundStyle(.red)
                Spacer()
                Button("Modifier", action: onEdit).buttonStyle(.glassProminent)
            }
            .font(.system(size: 13)).padding(14)
        }
        .frame(width: 340)
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.inter(11, .medium)).foregroundStyle(.secondary).textCase(.uppercase)
            content()
        }
    }
}
