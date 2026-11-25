import SwiftUI

struct EditView: View {
    @State var card: Card
    let allTags: [String]
    let columns: [Column]
    @State private var newTag = ""
    @State private var showCalendar = false
    let isNew: Bool
    let onSave: (Card) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Nouvelle carte" : "Modifier la carte").font(.inter(17, .semibold))
            field("Titre") { TextField("", text: $card.title).textFieldStyle(.roundedBorder) }
            field("Notes (Markdown)") {
                TextField("", text: $card.notes, axis: .vertical).lineLimit(4...10)
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
            field("Agents") {
                ForEach($card.agents) { $a in
                    HStack(spacing: 6) {
                        Menu {
                            ForEach(Agents.all) { k in agentButton(k) { a.name = k.key } }
                            Button("Autre…") { a.name = "" }
                        } label: { Label { Text(a.kind?.label ?? "Autre") } icon: { Image(nsImage: AgentIcon.menuImage(a.name)) } }
                            .fixedSize()
                        if a.kind == nil { TextField("Nom", text: $a.name).textFieldStyle(.roundedBorder).frame(width: 80) }
                        SuggestField(prompt: "Modèle", text: $a.model, options: a.kind?.models ?? [])
                        Menu {
                            Button("Aucun") { a.effort = "" }
                            ForEach(Agents.efforts(for: a.name), id: \.0) { e in Button(e.1) { a.effort = e.0 } }
                        } label: { Text(a.effort.isEmpty ? "Effort" : Agents.effortLabel(a.effort)) }
                            .fixedSize()
                        Button { card.agents.removeAll { $0.uid == a.uid } } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                Menu("Ajouter un agent") {
                    ForEach(Agents.all) { k in agentButton(k) { card.agents.append(Agent(name: k.key)) } }
                    Button("Autre…") { card.agents.append(Agent(name: "")) }
                }
                .fixedSize()
            }
            field("Priorité") {
                Picker("", selection: $card.priority) {
                    ForEach(Priority.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).fixedSize().frame(maxWidth: .infinity, alignment: .leading)
            }
            field("Colonne") {
                FlowLayout {
                    ForEach(columns) { col in
                        TagChip(tag: col.name, on: card.status == col.id, tint: col.color.color)
                            .onTapGesture { card.status = col.id }
                    }
                }
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
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button("Enregistrer") { onSave(card); dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(card.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.system(size: 13))  // system font on buttons: native look
        }
        .multilineTextAlignment(.leading)
        .font(.inter(13))
        .padding(24)
        .frame(width: 420)
    }

    private func agentButton(_ k: AgentKind, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label { Text(k.label) } icon: { Image(nsImage: AgentIcon.menuImage(k.key)) } }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.inter(12, .medium)).foregroundStyle(.secondary)
            content()
        }
    }
}

/// Text field with a menu of suggestions (free text stays possible).
struct SuggestField: View {
    let prompt: String
    @Binding var text: String
    let options: [String]

    var body: some View {
        HStack(spacing: 2) {
            TextField(prompt, text: $text).textFieldStyle(.roundedBorder)
            if !options.isEmpty {
                Menu { ForEach(options, id: \.self) { o in Button(o) { text = o } } } label: { Image(systemName: "chevron.down") }
                    .menuIndicator(.hidden).fixedSize()
            }
        }
    }
}
