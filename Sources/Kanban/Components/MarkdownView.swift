import SwiftUI

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, b in
                switch b {
                case .heading(let n, let s): Text(inlineMarkdown(s)).font(.inter([17, 15, 13][n - 1], .semibold)).padding(.top, 4)
                case .item(let d, let mark, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 6) { Text(mark).foregroundStyle(.secondary); Text(inlineMarkdown(s)) }.padding(.leading, CGFloat(d) * 14)
                case .quote(let s):
                    Text(inlineMarkdown(s)).foregroundStyle(.secondary).padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 3) }
                case .code(let s):
                    Text(s).font(.mono(12)).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                case .rule: Divider()
                case .para(let s): Text(inlineMarkdown(s))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }
}
