import SwiftUI

/// "New board" sheet: templates on the left, a live preview of the picked one on the right.
struct TemplatesView: View {
    let onPick: (Board) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = Template.all[0].id

    private var template: Template { Template.all.first { $0.id == selectedID }! }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 240)
            Divider()
            detail
        }
        .frame(width: 900, height: 540).font(.inter(13))
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nouveau tableau").font(.mono(15, .bold)).padding([.horizontal, .top], 16).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Template.all) { t in
                        Button { selectedID = t.id } label: { row(t) }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 8)
            }
            Divider()
            Button {
                dismiss()
                DispatchQueue.main.async { if let b = BoardIO.importBoard() { onPick(b) } }
            } label: { Label("Importer un fichier JSON…", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(.plain).padding(14)
        }
    }

    private func row(_ t: Template) -> some View {
        HStack(spacing: 10) {
            Image(systemName: t.icon).font(.system(size: 13, weight: .medium)).foregroundStyle(t.color)
                .frame(width: 28, height: 28).background(t.color.opacity(0.15), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(t.name).font(.inter(13, .medium))
                Text("\(t.columns.count) colonnes").font(.inter(11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8).contentShape(Rectangle())
        .background(selectedID == t.id ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: selectedID)
    }

    // MARK: Preview

    private var detail: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(template.name).font(.mono(18, .bold))
                Text(template.blurb).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(template.columns.enumerated()), id: \.offset) { i, col in
                        miniColumn(col, items: template.items.filter { min($0.col, template.columns.count - 1) == i })
                    }
                }.padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)
            .id(selectedID)
            .transition(.opacity)
            HStack {
                Spacer()
                Button("Fermer", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Créer le tableau") { onPick(template.makeBoard()); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.controlSize(.large)
        }
        .padding(20).frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.15), value: selectedID)
    }

    private func miniColumn(_ col: Template.Col, items: [Template.Item]) -> some View {
        let c = col.color.color
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(c).frame(width: 7, height: 7)
                Text(col.name).font(.mono(11, .bold)).foregroundStyle(c).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(items.count)").font(.inter(10, .semibold)).foregroundStyle(c)
            }.padding(.bottom, 2)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(item.priority.color).frame(width: 6, height: 6).padding(.top, 4)
                    Text(item.title).font(.inter(11)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.shadow(.drop(color: .black.opacity(0.08), radius: 3, y: 1)), in: .rect(cornerRadius: 9, style: .continuous))
            }
            Spacer(minLength: 0)
        }
        .padding(10).frame(width: 150).frame(maxHeight: .infinity, alignment: .top)
        .background(c.opacity(0.12), in: .rect(cornerRadius: 16, style: .continuous))
    }
}
