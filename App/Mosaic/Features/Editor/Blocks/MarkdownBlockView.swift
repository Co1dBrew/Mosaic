import SwiftUI
import MosaicKit

/// Renders the lightweight Markdown of a text block (headings, bold, italic,
/// bullet/numbered lists, dividers). Inline styling uses SwiftUI's Markdown
/// `AttributedString`; block structure is rendered line-by-line via the pure
/// `MarkdownText` parsers (MosaicKit).
struct MarkdownBlockView: View {
    let markdown: String

    private var lines: [String] { markdown.components(separatedBy: "\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(for: line)
            }
        }
    }

    @ViewBuilder private func row(for raw: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if MarkdownText.isDivider(trimmed) {
            Divider().padding(.vertical, 2)
        } else if let heading = MarkdownText.headingLevel(of: raw) {
            inline(heading.text).font(headingFont(heading.level)).bold()
        } else if let bullet = MarkdownText.bulletContent(of: raw) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text("•").foregroundStyle(.secondary)
                inline(bullet)
            }
        } else if let ordered = MarkdownText.orderedItem(of: raw) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text("\(ordered.number).").foregroundStyle(.secondary).monospacedDigit()
                inline(ordered.text)
            }
        } else if trimmed.isEmpty {
            Color.clear.frame(height: 4)
        } else {
            inline(raw)
        }
    }

    private func inline(_ string: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(string)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        default: return .headline
        }
    }
}
