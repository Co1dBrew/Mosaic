import SwiftUI
import UIKit

/// 图片块（PRD §4.3.3 · `UI_REDESIGN.md` v2 §3.8）。
///
/// v2 去掉了缩略图下方那个**常驻的「添加图片说明」输入框** —— 多数时候它是空的，
/// 每张图都为一个极少填的字段常驻一行。改为：**有说明才显示说明**，
/// 加/改说明进长按菜单。
struct ImageBlockView: View {
    @Bindable var block: Block
    let onEdit: () -> Void

    @State private var showFullScreen = false
    @State private var showCaptionEditor = false
    @State private var draftCaption = ""
    private let mediaStore = MediaStore.shared

    private var thumbnailURL: URL? {
        let path = block.thumbnailRelativePath.isEmpty ? block.imageRelativePath : block.thumbnailRelativePath
        return path.isEmpty ? nil : mediaStore.absoluteURL(for: path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let thumbnailURL, let image = UIImage(contentsOfFile: thumbnailURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { showFullScreen = true }
                    .accessibilityLabel("图片,点按查看大图")
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(height: 120)
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }

            if !block.caption.isEmpty {
                Text(block.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contextMenu {
            Button {
                draftCaption = block.caption
                showCaptionEditor = true
            } label: {
                Label(block.caption.isEmpty ? "添加说明" : "编辑说明", systemImage: "text.below.photo")
            }
        }
        .alert(block.caption.isEmpty ? "添加图片说明" : "编辑图片说明", isPresented: $showCaptionEditor) {
            TextField("说明", text: $draftCaption)
            Button("取消", role: .cancel) { }
            Button("保存") {
                block.caption = draftCaption.trimmingCharacters(in: .whitespacesAndNewlines)
                onEdit()
            }
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            if !block.imageRelativePath.isEmpty {
                ImageViewer(url: mediaStore.absoluteURL(for: block.imageRelativePath))
            }
        }
        .accessibilityIdentifier("block.image.\(block.id.uuidString)")
    }
}
