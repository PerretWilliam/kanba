import Foundation

/// What the board view shows: priority / tag / agent / text. screen state, never saved: an AI client can set it
/// (MCP set_filter) and the user sees the result. Reset whenever the tab changes.
struct ViewFilter: Codable, Equatable {
    var priority: Priority?
    var tag: String?
    var agent: String?   // agent key ("claude", "me"…), or part of a model name ("opus")
    var query: String

    init(priority: Priority? = nil, tag: String? = nil, agent: String? = nil, query: String = "") {
        self.priority = priority; self.tag = tag; self.agent = agent; self.query = query
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority)
        tag = try c.decodeIfPresent(String.self, forKey: .tag)
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        query = try c.decodeIfPresent(String.self, forKey: .query) ?? ""
    }

    var isEmpty: Bool { self == ViewFilter() }
    /// Chips active (the search text has its own field).
    var hasChips: Bool { priority != nil || tag != nil || agent != nil }

    func matches(_ card: Card) -> Bool {
        if let priority, card.priority != priority { return false }
        if let tag, !card.tags.contains(tag) { return false }
        if let agent {
            let q = agent.lowercased()
            if !card.agents.contains(where: { $0.key == q || $0.name.lowercased() == q || $0.model.localizedCaseInsensitiveContains(q) }) { return false }
        }
        return query.isEmpty || ([card.title, card.notes] + card.tags + card.agents.flatMap { [$0.label, $0.model] }).contains { $0.localizedStandardContains(query) }
    }
}
