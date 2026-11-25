import SwiftUI

struct FilterPanel: View {
    @Binding var filter: Priority?
    @Binding var tag: String?
    @Binding var agent: String?
    let tags: [String]
    let agents: [Agent]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Priorité").font(.inter(12, .medium)).foregroundStyle(.secondary)
            FlowLayout {
                ForEach(Priority.allCases) { p in
                    TagChip(tag: p.label, on: filter == p, tint: p.color)
                        .onTapGesture { filter = filter == p ? nil : p }
                }
            }
            if !tags.isEmpty {
                Text("Tag").font(.inter(12, .medium)).foregroundStyle(.secondary)
                FlowLayout {
                    ForEach(tags, id: \.self) { t in
                        TagChip(tag: t, on: tag == t).onTapGesture { tag = tag == t ? nil : t }
                    }
                }
            }
            if !agents.isEmpty {
                Text("Agent").font(.inter(12, .medium)).foregroundStyle(.secondary)
                FlowLayout {
                    ForEach(agents) { a in
                        HStack(spacing: 4) { AgentIcon(name: a.name).frame(width: 12, height: 12); TagChip(tag: a.label, on: agent == a.key, tint: a.kind?.color) }
                            .onTapGesture { agent = agent == a.key ? nil : a.key }
                    }
                }
            }
            if filter != nil || tag != nil || agent != nil {
                Button("Réinitialiser") { filter = nil; tag = nil; agent = nil }
            }
        }
        .padding(16).frame(width: 300, alignment: .leading)
        // The popover would otherwise inherit the header's glass / circle / large button style.
        .buttonStyle(.automatic).buttonBorderShape(.automatic).controlSize(.regular)
    }
}
