import SwiftUI

/// Text block editor. MVP uses plain text (PRD §4.3.1 "工期紧 MVP 可先纯文本");
/// the model stores a `String`, upgradeable to lightweight rich text later.
struct TextBlockView: View {
    @Bindable var block: Block
    let onEdit: () -> Void

    var body: some View {
        TextField("输入文字…", text: $block.text, axis: .vertical)
            .font(.body)
            .lineLimit(1...20)
            .onChange(of: block.text) { _, _ in onEdit() }
            .accessibilityLabel("文字内容块")
    }
}
