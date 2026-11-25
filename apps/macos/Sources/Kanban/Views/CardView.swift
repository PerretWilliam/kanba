import SwiftUI

struct CardView: View {
    let card: Card
    var isDone = false
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(card.title).font(.mono(13, .medium)).lineLimit(3)
                    .strikethrough(isDone)
            }
            if !card.notes.isEmpty {
                Text(inlineMarkdown(card.notes)).font(.inter(12)).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 8) {
                Text(card.priority.label).font(.inter(11, .semibold)).foregroundStyle(card.priority.color)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(card.priority.color.opacity(0.15), in: Capsule())
                if let due = card.due {
                    let late = !isDone && due < Calendar.current.startOfDay(for: .now)
                    Label(due.formatted(.dateTime.day().month(.abbreviated)), systemImage: "calendar")
                        .font(.inter(11)).foregroundStyle(late ? .red : .secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: -3) {
                    ForEach(card.agents.prefix(4)) { a in
                        AgentIcon(name: a.name).padding(3).frame(width: 18, height: 18)
                            .background(.background, in: Circle()).overlay(Circle().stroke(.quaternary))
                            .contentShape(Circle()).hoverTip(a.tooltip)
                    }
                }
            }
            if !card.tags.isEmpty {
                FlowLayout(spacing: 4) { ForEach(card.tags, id: \.self) { TagChip(tag: $0) } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.background.shadow(.drop(color: .black.opacity(0.08), radius: 5, y: 2)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.quaternary.opacity(0.6)))
        .opacity(isDone ? 0.6 : 1)
        .contentShape(Rectangle())
        .scaleEffect(hover ? 1.012 : 1)
        .animation(.easeOut(duration: 0.15), value: hover)
        .onHover { hover = $0 }
    }
}
