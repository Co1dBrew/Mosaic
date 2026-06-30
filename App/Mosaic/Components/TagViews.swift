import SwiftUI

/// A single tag chip. With `onRemove`, shows a delete affordance (editor); without,
/// it's read-only (card row / filter display).
struct TagChip: View {
    let text: String
    var isSelected: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Text(text)
                .font(.caption)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.caption2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除标签 \(text)")
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.14))
        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
        .clipShape(Capsule())
    }
}

/// Editable tag list for a card: removable chips + an add field. Pure display +
/// interaction; the de-dup/normalize logic lives in MosaicKit `TagUtilities`
/// (via `Card.addTag` / `removeTag`).
struct TagEditorView: View {
    @Bindable var card: Card
    var onChange: () -> Void = {}

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if !card.tags.isEmpty {
                FlowLayout(spacing: AppSpacing.sm) {
                    ForEach(card.tags, id: \.self) { tag in
                        TagChip(text: tag) {
                            card.removeTag(tag)
                            onChange()
                        }
                    }
                }
            }
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "tag").foregroundStyle(.secondary)
                TextField("添加标签", text: $draft)
                    .submitLabel(.done)
                    .onSubmit(addDraft)
                if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: addDraft) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func addDraft() {
        let value = draft
        draft = ""
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        card.addTag(value)
        onChange()
    }
}
