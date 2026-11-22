import Testing
import Foundation
@testable import Kanban

@Suite struct ModelTests {
    @Test func columnColors() {
        for c in ColumnColor.allCases { #expect(!c.label.isEmpty); _ = c.color }
        #expect(ColumnColor.red.label == "Rouge")
    }

    @Test func priorities() {
        #expect(Priority.allCases.map(\.label) == ["Basse", "Moyenne", "Haute"])
        for p in Priority.allCases { #expect(p.id == p.rawValue); _ = p.color }
    }

    @Test func cardDecodingIsTolerant() throws {
        let c = try JSONDecoder().decode(Card.self, from: Data("{}".utf8))
        #expect(c.title == "" && c.priority == .medium && c.agents.isEmpty && c.due == nil && c.tags.isEmpty)
        let full = #"{"id":"0F0F0F0F-0000-0000-0000-000000000001","title":"t","notes":"n","priority":2,"due":5,"status":"s","tags":["a"],"agents":[{"name":"claude"}]}"#
        let d = try JSONDecoder().decode(Card.self, from: Data(full.utf8))
        #expect(d.title == "t" && d.priority == .high && d.status == "s" && d.agents == [Agent(name: "claude")])
    }

    @Test func boardDefaults() throws {
        let b = Board(name: "x")
        #expect(b.columns.map(\.id) == ["todo", "doing", "done"] && b.closed == nil && b.parent == nil)
        let back = try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(b))
        #expect(back.id == b.id)
    }

    @Test func templatesBuildBoards() {
        #expect(!Template.all.isEmpty)
        for t in Template.all {
            let b = t.makeBoard()
            #expect(b.name == t.name && b.columns.count == t.columns.count && b.cards.count == t.items.count)
            #expect(b.cards.allSatisfy { c in b.columns.contains { $0.id == c.status } })
        }
    }

    @Test func toast() {
        #expect(Toast.actorName("claude-code") == "Claude")
        #expect(Toast.actorName("my-bot") == "my-bot")
        #expect(Toast(text: "a", actor: nil).actor == nil)
    }

    @Test func fontsAndLogosExist() {
        for k in Agents.all { if let l = k.logo { #expect(Logos.svg[l]?.contains("<path") == true, "\(k.key)") } }
    }
}

@Suite struct AgentTests {
    @Test func kindMatchesClientNames() {
        #expect(Agents.kind("codex-mcp-client")?.key == "codex")
        #expect(Agents.kind("Gemini-CLI")?.key == "gemini")
        #expect(Agents.kind("claude-code")?.key == "claude")
        #expect(Agents.kind("me")?.key == "me")
        #expect(Agents.kind("") == nil)
        #expect(Agents.kind("nobody-knows") == nil)
        #expect(Set(Agents.all.map(\.key)).count == Agents.all.count)
    }

    @Test func labelsAndDetail() {
        let a = Agent(name: "claude", model: "Opus 5.5", effort: "high")
        #expect(a.label == "Claude" && a.key == "claude" && a.kind?.key == "claude")
        #expect(a.detail == "Opus 5.5 · Élevé" && a.summary == "Claude · Opus 5.5 · Élevé")
        #expect(Agent(name: "claude").summary == "Claude")
        #expect(Agent(name: "Foo").label == "Foo" && Agent(name: "Foo").key == "foo")
        #expect(Agent(name: "").label == "Autre")
        #expect(Agents.effortLabel("MAX") == "Max" && Agents.effortLabel("weird") == "weird")
        #expect(Agent(name: "x", effort: "low").detail == "Faible")
        #expect(Agents.efforts(for: "gemini").map(\.0) == ["minimal", "low", "medium", "high", "xhigh"])
        #expect(Agents.efforts(for: "claude").map(\.0) == Agents.standardEfforts && Agents.efforts(for: "?").count == 5)
    }

    @Test func identityAndCoding() throws {
        let a = Agent(name: "a", model: "m", effort: "low"), b = Agent(name: "a", model: "m", effort: "low")
        #expect(a == b && a.id != b.id && Set([a, b]).count == 1)
        #expect(a != Agent(name: "a", model: "other", effort: "low"))
        let json = try String(decoding: JSONEncoder().encode(a), as: UTF8.self)
        #expect(!json.contains("uid"))
        #expect(try JSONDecoder().decode(Agent.self, from: Data("{}".utf8)) == Agent(name: ""))
        #expect(try JSONDecoder().decode(Agent.self, from: Data(json.utf8)) == a)
    }
}

@Suite struct MarkdownTests {
    @Test func blocks() {
        let md = "# Title\n###### deep\n#nospace\n---\n> quote\n- a\n  * [ ] todo\n- [x] done\n+ [X] Done\n1. one\n12. twelve\n3.nope\n\nplain\n```\ncode\n  indented\n```\n```\nunterminated"
        #expect(MarkdownBlock.parse(md) == [
            .heading(1, "Title"), .heading(3, "deep"), .para("#nospace"), .rule, .quote("quote"),
            .item(0, "•", "a"), .item(1, "☐", "todo"), .item(0, "☑", "done"), .item(0, "☑", "Done"),
            .item(0, "1.", "one"), .item(0, "12.", "twelve"), .para("3.nope"), .para("plain"),
            .code("code\n  indented"), .code("unterminated")])
        #expect(MarkdownBlock.parse("") == [])
        #expect(MarkdownBlock.parse("####### seven") == [.para("####### seven")])
    }

    @Test func inline() {
        #expect(String(inlineMarkdown("a **b** `c`").characters) == "a b c")
        #expect(String(inlineMarkdown("[x](").characters).contains("x"))
    }
}
