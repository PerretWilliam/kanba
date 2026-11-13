import SwiftUI

/// Sheet listing the starter boards; picking one hands it back to the caller.
struct TemplatesView: View {
    let onPick: (Template) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Modèles").font(.mono(18, .bold))
                Text("Choisis un tableau de départ.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                ForEach(Template.all) { t in
                    Button { onPick(t); dismiss() } label: { tile(t) }
                        .buttonStyle(.plain)
                        .onHover { hovered = $0 ? t.id : nil }
                }
            }
            HStack { Spacer(); Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(20).frame(width: 520).font(.inter(13))
    }

    private func tile(_ t: Template) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: t.icon).font(.system(size: 17, weight: .medium)).foregroundStyle(t.color)
                .frame(width: 34, height: 34).background(t.color.opacity(0.15), in: .rect(cornerRadius: 9, style: .continuous))
            Text(t.name).font(.mono(13, .medium))
            Text(t.blurb).font(.inter(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(t.items.isEmpty ? "Aucune carte" : "\(t.items.count) cartes")
                .font(.inter(11)).foregroundStyle(.tertiary)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .background(.quaternary.opacity(hovered == t.id ? 0.9 : 0.5), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(t.color.opacity(hovered == t.id ? 0.6 : 0), lineWidth: 1.5))
        .scaleEffect(hovered == t.id ? 1.015 : 1)
        .animation(.snappy(duration: 0.15), value: hovered)
    }
}
