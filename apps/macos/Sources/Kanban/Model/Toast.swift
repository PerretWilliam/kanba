import Foundation

/// A short message. `actor` is nil for the user, otherwise the name of the AI client that acted (e.g. "claude-code").
struct Toast: Identifiable, Equatable {
    let id: UUID
    var text: String
    var actor: String?

    init(text: String, actor: String? = nil) { id = UUID(); self.text = text; self.actor = actor }

    static func actorName(_ a: String) -> String { Agents.kind(a)?.label ?? a }
}
