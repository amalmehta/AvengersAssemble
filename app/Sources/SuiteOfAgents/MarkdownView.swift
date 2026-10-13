import SuiteCore
import SwiftUI

/// A small block-level Markdown renderer: headings, paragraphs, lists, quotes, code fences and rules.
/// Inline styling (bold, italic, code, links) uses AttributedString(markdown:).
struct MarkdownView: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, s):
            inline(s)
                .font(level == 1 ? .title2.weight(.bold) : level == 2 ? .title3.weight(.semibold) : .headline)
                .padding(.top, level == 1 ? 0 : 4)
        case let .paragraph(s):
            inline(s).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
        case let .bullet(items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        inline(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case let .numbered(items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary)
                        inline(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case let .quote(s):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.secondary.opacity(0.4)).frame(width: 3)
                inline(s).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case let .code(s):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(s).font(.system(.callout, design: .monospaced)).padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        case .rule:
            Divider()
        }
    }

    private func inline(_ s: String) -> Text {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let a = try? AttributedString(markdown: s, options: opts) { return Text(a) }
        return Text(s)
    }
}

enum MarkdownBlock: Equatable {
    case heading(Int, String)
    case paragraph(String)
    case bullet([String])
    case numbered([String])
    case quote(String)
    case code(String)
    case rule
}

enum MarkdownBlocks {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var para: [String] = []
        var bullets: [String] = []
        var numbers: [String] = []
        var code: [String]? = nil

        func flush() {
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: " "))); para = [] }
            if !bullets.isEmpty { blocks.append(.bullet(bullets)); bullets = [] }
            if !numbers.isEmpty { blocks.append(.numbered(numbers)); numbers = [] }
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if code != nil {
                if line.hasPrefix("```") { blocks.append(.code(code!.joined(separator: "\n"))); code = nil }
                else { code!.append(raw) }
                continue
            }
            if line.hasPrefix("```") { flush(); code = []; continue }
            if line.isEmpty { flush(); continue }
            if line == "---" || line == "***" || line == "___" { flush(); blocks.append(.rule); continue }
            if line.hasPrefix("#") {
                let level = line.prefix { $0 == "#" }.count
                if level <= 6, line.dropFirst(level).first == " " {
                    flush()
                    blocks.append(.heading(level, String(line.dropFirst(level + 1))))
                    continue
                }
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                if !para.isEmpty || !numbers.isEmpty { flush() }
                bullets.append(String(line.dropFirst(2)))
                continue
            }
            if let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }),
               !line[..<dot].isEmpty, line[..<dot].allSatisfy(\.isNumber),
               line[line.index(after: dot)...].first == " " {
                if !para.isEmpty || !bullets.isEmpty { flush() }
                numbers.append(String(line[line.index(dot, offsetBy: 2)...]))
                continue
            }
            if line.hasPrefix(">") {
                flush()
                blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }
            // Continuation of a list item (indented line) appends to the last item.
            if raw.hasPrefix("  "), !bullets.isEmpty { bullets[bullets.count - 1] += " " + line; continue }
            if raw.hasPrefix("  "), !numbers.isEmpty { numbers[numbers.count - 1] += " " + line; continue }
            if !bullets.isEmpty || !numbers.isEmpty { flush() }
            para.append(line)
        }
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}
