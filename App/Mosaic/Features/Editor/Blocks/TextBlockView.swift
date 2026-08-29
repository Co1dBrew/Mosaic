import SwiftUI
import MosaicKit

/// 文字块（`UI_REDESIGN.md` v2 §3.8）。
///
/// **零按钮**：聚焦即显示 Markdown 源码，失焦即渲染。原来每块右下角有一个
/// 「编辑 / 预览」切换按钮 —— 一篇十个块的笔记就有十个这样的按钮，而它们表达的
/// 是同一件事（我现在在不在编辑）。焦点本身已经表达了它。
///
/// Markdown 工具条只在聚焦时出现（`RichMarkdownEditor` 的 inputAccessoryView），
/// 所以它也不占常驻像素。
struct TextBlockView: View {
    @Bindable var block: Block
    let onEdit: () -> Void
    /// 当前聚焦的块。由笔记页持有 —— 「末尾永远有一个可写文字块」与
    /// 「插入媒体后自动补块并聚焦」都要求由页面来指定焦点落在谁身上。
    @Binding var focusedBlockID: UUID?

    private var isFocused: Binding<Bool> {
        Binding(get: { focusedBlockID == block.id },
                set: { focused in
                    if focused { focusedBlockID = block.id }
                    else if focusedBlockID == block.id { focusedBlockID = nil }
                })
    }

    private var textBinding: Binding<String> {
        Binding(get: { block.text }, set: { block.text = $0 })
    }

    var body: some View {
        Group {
            if isFocused.wrappedValue {
                RichMarkdownEditor(text: textBinding, isFocused: isFocused, onChange: onEdit)
                    .frame(minHeight: 30)
                    .onChange(of: block.text) { _, _ in onEdit() }
                    .accessibilityLabel("文字内容块")
            } else if block.text.isEmpty {
                // 空块失焦时渲染出来是**一片什么都没有**，既看不见也点不到 ——
                // 而 §3.5 要求末尾永远有一个可写的文字块。给它一个可点的占位。
                Text("写点什么…")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { focusedBlockID = block.id }
                    .accessibilityLabel("空文字块，点按开始输入")
            } else {
                MarkdownBlockView(markdown: block.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { focusedBlockID = block.id }
            }
        }
        .accessibilityIdentifier("block.text.\(block.id.uuidString)")
    }
}
