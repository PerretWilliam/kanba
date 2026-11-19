import SwiftUI

/// git-diff-like review of what an AI client proposed: tick what to keep, apply the rest is dropped.
struct ReviewView: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var skipped: Set<UUID> = []

    private var chosen: Set<UUID> { Set(store.review.map(\.id)).subtracting(skipped) }
    private var count: Int { store.review.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ActorIcon(actor: store.proposal?.actor ?? "claude").frame(width: 20, height: 20)
                Text("\(store.proposal.map { Toast.actorName($0.actor) } ?? "L'IA") propose \(count) modification\(count > 1 ? "s" : "")")
                    .font(.inter(15, .semibold))
                Spacer()
            }
            .padding(16)
            Divider()
            ScrollView { VStack(spacing: 8) { ForEach(store.review) { row($0) } }.padding(16) }
            Divider()
            HStack {
                Button("Tout refuser", role: .destructive) { store.reject(); dismiss() }
                Spacer()
                Button("Plus tard") { dismiss() }
                Button("Appliquer (\(chosen.count))") { store.accept(chosen); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(chosen.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 540, height: 540).font(.inter(13))
        .onChange(of: store.review.isEmpty) { if store.review.isEmpty { dismiss() } }
    }

    private func row(_ ch: Change) -> some View {
        let on = Binding(get: { !skipped.contains(ch.id) }, set: { if $0 { skipped.remove(ch.id) } else { skipped.insert(ch.id) } })
        let tint: Color = ch.kind == .add ? .green : ch.kind == .remove ? .red : .orange
        return HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: on).toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: ch.kind == .add ? "plus.circle.fill" : ch.kind == .remove ? "minus.circle.fill" : "pencil.circle.fill")
                        .foregroundStyle(tint)
                    Text(ch.title).font(.inter(13, .semibold))
                    if !ch.scope.isEmpty { Text(ch.scope).foregroundStyle(.secondary) }
                }
                ForEach(Array(ch.lines.enumerated()), id: \.offset) { _, l in
                    VStack(alignment: .leading, spacing: 2) {
                        if let o = l.old { diffLine("−", l.label, o, .red) }
                        if let n = l.new { diffLine("+", l.label, n, .green) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
        .opacity(on.wrappedValue ? 1 : 0.45)
    }

    private func diffLine(_ sign: String, _ label: String, _ text: String, _ color: Color) -> some View {
        Text("\(sign) \(label): \(text)").font(.mono(12)).foregroundStyle(color).lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: .rect(cornerRadius: 4))
    }
}
