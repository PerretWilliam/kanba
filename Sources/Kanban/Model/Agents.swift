import SwiftUI

/// An AI (or the user) known to the app: icon, colour and suggested models. Matched by substring, so an MCP
/// client name like "codex-mcp-client" or "gemini-cli" resolves to the right one. Unknown names still work (generic icon).
struct AgentKind: Identifiable {
    let key: String, label: String, symbol: String, color: Color
    var logo: String?   // key in Logos.svg (Simple Icons); nil = no official logo available, the SF symbol is shown
    var match: [String] = [], models: [String] = []
    var efforts = Agents.standardEfforts   // levels the vendor documents for its models
    var id: String { key }
}

enum Agents {
    // Order matters: first match wins ("codex" before "gpt").
    static let all: [AgentKind] = [
        .init(key: "me", label: "Moi", symbol: "person.fill", color: .green, match: ["me", "moi", "user", "utilisateur"]),
        .init(key: "claude", label: "Claude", symbol: "sparkle", color: Color(red: 0.851, green: 0.467, blue: 0.341), logo: "claude", match: ["claude", "anthropic"],
              models: ["Fable 5.2", "Opus 5.5", "Sonnet 5.5", "Haiku 5.5"]),
        .init(key: "codex", label: "Codex", symbol: "terminal.fill", color: .indigo, logo: "openai", match: ["codex"], models: Agents.openAI),
        .init(key: "chatgpt", label: "ChatGPT", symbol: "bubbles.and.sparkles.fill", color: .mint, logo: "openai", match: ["chatgpt", "openai", "gpt"], models: Agents.openAI),
        .init(key: "gemini", label: "Gemini", symbol: "sparkles", color: .blue, logo: "googlegemini", match: ["gemini", "google", "bard"], models: ["Gemini 4 Carbon", "Gemini 4 Neon", "Gemini 4 Hydrogen", "Gemini 4 Argon", "Gemini 3.8 Flash", "Gemini 3.1 Pro"], efforts: ["minimal", "low", "medium", "high", "xhigh"]),
        .init(key: "copilot", label: "Copilot", symbol: "paperplane.fill", color: .purple, logo: "githubcopilot", match: ["copilot"],
              models: ["GPT-6.2 Sol", "GPT-6.2 Astra", "Claude Sonnet 5.5", "Claude Opus 5.5", "Gemini 4 Carbon", "Grok 4.7"]),
        .init(key: "cursor", label: "Cursor", symbol: "cursorarrow", color: .gray, logo: "cursor", match: ["cursor"]),
        .init(key: "windsurf", label: "Windsurf", symbol: "wind", color: .teal, logo: "windsurf", match: ["windsurf", "codeium"]),
        .init(key: "mistral", label: "Mistral", symbol: "flame.fill", color: .orange, logo: "mistralai", match: ["mistral", "le chat", "vibe"], models: ["Mistral Large 4", "Mistral Medium 3.5", "Mistral Small 4", "Codestral"]),
        .init(key: "deepseek", label: "DeepSeek", symbol: "water.waves", color: .cyan, logo: "deepseek", match: ["deepseek"], models: ["DeepSeek V4 Pro", "DeepSeek V4.1 Flash"]),
        .init(key: "grok", label: "Grok", symbol: "bolt.fill", color: .primary, match: ["grok", "xai"], models: ["Grok 4.7", "Grok 4.6", "Grok 4.5", "Grok Build"]),
        .init(key: "perplexity", label: "Perplexity", symbol: "magnifyingglass", color: .teal, logo: "perplexity", match: ["perplexity"]),
        .init(key: "llama", label: "Llama", symbol: "pawprint.fill", color: .blue, logo: "meta", match: ["llama", "meta"]),
        .init(key: "qwen", label: "Qwen", symbol: "q.circle.fill", color: .purple, logo: "qwen", match: ["qwen"]),
        .init(key: "kimi", label: "Kimi", symbol: "moon.stars.fill", color: .indigo, logo: "kimi", match: ["kimi", "moonshot"], models: ["Kimi K3"]),
        .init(key: "zed", label: "Zed", symbol: "z.circle.fill", color: .orange, logo: "zedindustries", match: ["zed"]),
        .init(key: "cline", label: "Cline", symbol: "curlybraces", color: .pink, logo: "cline", match: ["cline", "roo"]),
        .init(key: "aider", label: "Aider", symbol: "hammer.fill", color: .brown, match: ["aider"]),
        .init(key: "opencode", label: "OpenCode", symbol: "chevron.left.forwardslash.chevron.right", color: .green, logo: "opencode", match: ["opencode"]),
        .init(key: "goose", label: "Goose", symbol: "bird.fill", color: .gray, match: ["goose"]),
    ]
    static let openAI = ["GPT-6.2 Astra", "GPT-6.2 Sol", "GPT-6.1 Terra", "GPT-6 Luna"]
    static let standardEfforts = ["low", "medium", "high", "xhigh", "max"]
    static let efforts = [("minimal", "Minimal"), ("low", "Faible"), ("medium", "Moyen"), ("high", "Élevé"), ("xhigh", "Très élevé"), ("max", "Max")]

    static func kind(_ name: String) -> AgentKind? {
        let n = name.lowercased()
        return n.isEmpty ? nil : all.first { k in k.match.contains { n.contains($0) } }
    }
    /// Effort levels offered for this agent name (its vendor's documented levels).
    static func efforts(for name: String) -> [(String, String)] {
        let allowed = kind(name)?.efforts ?? standardEfforts
        return efforts.filter { allowed.contains($0.0) }
    }
    static func effortLabel(_ e: String) -> String { efforts.first { $0.0 == e.lowercased() }?.1 ?? e }
}

/// One assignee of a card: the user ("me") or an AI, with the model and effort level it should use.
struct Agent: Identifiable, Hashable, Codable {
    var name: String
    var model = ""
    var effort = ""
    var uid = UUID()   // UI identity only, not saved

    enum CodingKeys: String, CodingKey { case name, model, effort }
    init(name: String, model: String = "", effort: String = "") { self.name = name; self.model = model; self.effort = effort }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        effort = try c.decodeIfPresent(String.self, forKey: .effort) ?? ""
    }
    static func == (a: Agent, b: Agent) -> Bool { a.name == b.name && a.model == b.model && a.effort == b.effort }
    func hash(into h: inout Hasher) { h.combine(name); h.combine(model); h.combine(effort) }

    var id: UUID { uid }
    var kind: AgentKind? { Agents.kind(name) }
    var key: String { kind?.key ?? name.lowercased() }
    var label: String { kind?.label ?? (name.isEmpty ? "Autre" : name) }
    /// "Opus 5.5 · Élevé"
    var detail: String { [model, effort.isEmpty ? "" : Agents.effortLabel(effort)].filter { !$0.isEmpty }.joined(separator: " · ") }
    var summary: String { ([label] + (detail.isEmpty ? [] : [detail])).joined(separator: " · ") }
}

