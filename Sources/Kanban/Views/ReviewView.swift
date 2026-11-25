import SwiftUI

/// git-diff-like review of what an AI client proposed: tick what to keep, apply the rest is dropped.
struct ReviewView: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var skipped: Set<UUID> = []
    @State private var openID: UUID?   // change shown in the detail pane on the right
    private var open: Change? { store.review.first { $0.id == openID } }

    private var chosen: Set<UUID> { Set(store.review.map(\.id)).subtracting(skipped) }
    private var count: Int { store.review.count }

    var body: some View {
        HStack(spacing: 0) {
            list
            if let c = open { Divider(); detail(c).transition(.move(edge: .trailing)) }
        }
        .frame(width: open == nil ? 540 : 900, height: 540).font(.inter(13))
        .animation(.snappy(duration: 0.25), value: openID)
        .onChange(of: store.review.isEmpty) { if store.review.isEmpty { dismiss() } }
    }

    private var list: some View {
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
        .frame(width: 540)
    }

    /// Full, untruncated before/after of one change.
    private func detail(_ ch: Change) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(ch.title).font(.inter(14, .semibold)).lineLimit(2)
                Spacer()
                Button { openID = nil } label: { Image(systemName: "xmark").padding(4).contentShape(.rect) }.buttonStyle(.borderless)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !ch.scope.isEmpty { Text(ch.scope).foregroundStyle(.secondary) }
                    ForEach(Array(ch.lines.enumerated()), id: \.offset) { _, l in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(l.label).font(.inter(11, .medium)).foregroundStyle(.secondary).textCase(.uppercase)
                            if let o = l.old { full("−", o, .red) }
                            if let n = l.new { full("+", n, .green) }
                        }
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 360)
    }

    private func full(_ sign: String, _ text: String, _ color: Color) -> some View {
        Text("\(sign) \(text)").font(.mono(12)).foregroundStyle(color).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(8).background(color.opacity(0.12), in: .rect(cornerRadius: 6))
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
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: openID == ch.id ? 1.5 : 0))
        .contentShape(.rect).onTapGesture { openID = openID == ch.id ? nil : ch.id }
    }

    private func diffLine(_ sign: String, _ label: String, _ text: String, _ color: Color) -> some View {
        Text("\(sign) \(label): \(text)").font(.mono(12)).foregroundStyle(color).lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: .rect(cornerRadius: 4))
    }
}
