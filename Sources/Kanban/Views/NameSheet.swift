import SwiftUI

/// Tiny "type a name" sheet shared by tab and column renaming.
struct NameSheet: View {
    let title: String
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.inter(15, .semibold))
            TextField("", text: $text).textFieldStyle(.roundedBorder).onSubmit(save)
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer", action: save).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(trimmed.isEmpty)
            }
        }
        .padding(20).frame(width: 320).font(.inter(13))
    }

    private func save() { guard !trimmed.isEmpty else { return }; onSave(trimmed); dismiss() }
}
