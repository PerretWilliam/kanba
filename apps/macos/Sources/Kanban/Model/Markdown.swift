import Foundation

/// Inline markdown (bold, italic, code, links) in one string; line breaks are kept.
func inlineMarkdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
}

/// Block structure of card notes: headings, bullet / numbered / task lists, quotes, code blocks, rules.
/// ponytail: no tables or nested blockquotes, add a markdown library if notes need them.
enum MarkdownBlock: Equatable {
    case heading(Int, String), item(Int, String, String), quote(String), code(String), rule, para(String)

    static func parse(_ text: String) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = [], code: [String]?
        for raw in text.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"))); code = nil } else { code = [] }
                continue
            }
            if code != nil { code!.append(raw); continue }
            let depth = raw.prefix { $0 == " " }.count / 2
            let hashes = t.prefix { $0 == "#" }.count
            let digits = t.prefix { $0.isNumber }
            if t.isEmpty { continue }
            else if hashes > 0, hashes <= 6, t.dropFirst(hashes).first == " " { out.append(.heading(min(hashes, 3), String(t.dropFirst(hashes + 1)))) }
            else if ["---", "***", "___"].contains(t) { out.append(.rule) }
            else if t.hasPrefix("> ") { out.append(.quote(String(t.dropFirst(2)))) }
            else if let f = t.first, "-*+".contains(f), t.dropFirst().first == " " {
                let rest = String(t.dropFirst(2))
                if rest.hasPrefix("[ ] ") { out.append(.item(depth, "☐", String(rest.dropFirst(4)))) }
                else if rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") { out.append(.item(depth, "☑", String(rest.dropFirst(4)))) }
                else { out.append(.item(depth, "•", rest)) }
            }
            else if !digits.isEmpty, t.dropFirst(digits.count).hasPrefix(". ") { out.append(.item(depth, "\(digits).", String(t.dropFirst(digits.count + 2)))) }
            else { out.append(.para(t)) }
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        return out
    }
}
