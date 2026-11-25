import SwiftUI

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

/// Who did it: a check for the user, the AI client's icon (see Agents) for an AI.
struct ActorIcon: View {
    let actor: String?
    var body: some View {
        if let a = actor { AgentIcon(name: a) }
        else { Image(systemName: "checkmark.circle.fill").resizable().scaledToFit().foregroundStyle(.green) }
    }
}
