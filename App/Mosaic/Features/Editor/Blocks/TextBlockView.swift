import SwiftUI
import MosaicKit

/// Text block: MVP-level lightweight rich text stored as Markdown in `block.text`
/// (PRD §4.3.1). Editing uses `RichMarkdownEditor` (UITextView + Markdown
/// toolbar); a per-block toggle switches to a rendered `MarkdownBlockView`
/// preview. Plain-text blocks keep working unchanged (Markdown is a superset).
struct TextBlockView: View {
    let block: Block
    let onEdit: () -> Void

    @State private var isEditing: Bool

    init(block: Block, onEdit: @escaping () -> Void) {
        self.block = block
        self.onEdit = onEdit
        // Start editing for empty/plain blocks; show the rendered preview for
        // blocks that already use formatting.
        _isEditing = State(initialValue: block.text.isEmpty || !MarkdownText.hasFormatting(block.text))
    }

    private var textBinding: Binding<String> {
        Binding(get: { block.text }, set: { block.text = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if isEditing {
                RichMarkdownEditor(text: textBinding, onChange: onEdit)
                    .frame(minHeight: 30)
                    .onChange(of: block.text) { _, _ in onEdit() }
                    .accessibilityLabel("文字内容块")
            } else {
                MarkdownBlockView(markdown: block.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { isEditing = true }
            }

            if !block.text.isEmpty {
                HStack {
                    Spacer()
                    Button { isEditing.toggle() } label: {
                        Label(isEditing ? "预览" : "编辑",
                              systemImage: isEditing ? "eye" : "pencil")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
