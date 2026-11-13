import SwiftUI

struct EditView: View {
    @State var card: Card
    let allTags: [String]
    @State private var newTag = ""
    @State private var showCalendar = false
    let isNew: Bool
    let onSave: (Card) -> Void
    let onDelete: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Nouvelle carte" : "Modifier la carte").font(.inter(17, .semibold))
            field("Titre") { TextField("", text: $card.title).textFieldStyle(.roundedBorder) }
            field("Notes") {
                TextField("", text: $card.notes, axis: .vertical).lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }
            field("Tags") {
                FlowLayout {
                    ForEach(Array(Set(allTags + card.tags)).sorted(), id: \.self) { tag in
                        let on = card.tags.contains(tag)
                        TagChip(tag: tag, on: on).onTapGesture {
                            if on { card.tags.removeAll { $0 == tag } } else { card.tags.append(tag) }
                        }
                    }
                }
                TextField("Nouveau tag, puis Entrée", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let t = newTag.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty && !card.tags.contains(t) { card.tags.append(t) }
                        newTag = ""
                    }
            }
            field("Priorité") {
                Picker("", selection: $card.priority) {
                    ForEach(Priority.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).fixedSize().frame(maxWidth: .infinity, alignment: .leading)
            }
            field("Statut") {
                Picker("", selection: $card.status) {
                    ForEach(Status.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).fixedSize().frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Toggle("Échéance", isOn: Binding(
                    get: { card.due != nil },
                    set: { card.due = $0 ? (card.due ?? .now) : nil }))
                Spacer()
                if let due = card.due {
                    Button(due.formatted(.dateTime.day().month(.wide).year())) { showCalendar = true }
                        .buttonStyle(.glass)
                        .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                            DatePicker("", selection: Binding(get: { due }, set: { card.due = $0 }),
                                       displayedComponents: .date)
                                .datePickerStyle(.graphical).labelsHidden().padding(12)
                        }
                }
            }
            HStack {
                if !isNew { Button("Supprimer", role: .destructive) { onDelete(card.id); dismiss() } }
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") { onSave(card); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(card.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.large)
        }
        .multilineTextAlignment(.leading)
        .font(.inter(13))
        .padding(24)
        .frame(width: 420)
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.inter(12, .medium)).foregroundStyle(.secondary)
            content()
        }
    }
}
