import SwiftUI

/// A short message. `actor` is nil for the user, otherwise the name of the AI client that acted (e.g. "claude-code").
struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var actor: String?

    static func actorName(_ a: String) -> String { a.lowercased().contains("claude") ? "Claude" : a }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            ActorIcon(actor: toast.actor).frame(width: 16, height: 16)
            Text(toast.text).font(.inter(13, .medium)).lineLimit(1)
        }
        .padding(.horizontal, 14).frame(height: 38)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .allowsHitTesting(false)
    }
}

/// Who did it: a check for the user, Claude's mark for Claude, a generic spark for any other AI client.
struct ActorIcon: View {
    let actor: String?
    var body: some View {
        if let a = actor {
            if a.lowercased().contains("claude") { ClaudeMark() }
            else { Image(systemName: "sparkle").resizable().scaledToFit().foregroundStyle(.secondary) }
        } else {
            Image(systemName: "checkmark.circle.fill").resizable().scaledToFit().foregroundStyle(.green)
        }
    }
}
