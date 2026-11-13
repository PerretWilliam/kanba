import SwiftUI

struct FilterPanel: View {
    @Binding var filter: Priority?
    @Binding var tag: String?
    let tags: [String]

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
            if filter != nil || tag != nil {
                Button("Réinitialiser") { filter = nil; tag = nil }
            }
        }
        .padding(16).frame(width: 300, alignment: .leading)
        // The popover would otherwise inherit the header's glass / circle / large button style.
        .buttonStyle(.automatic).buttonBorderShape(.automatic).controlSize(.regular)
    }
}
