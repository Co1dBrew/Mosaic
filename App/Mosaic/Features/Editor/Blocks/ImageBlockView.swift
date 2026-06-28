import SwiftUI
import UIKit

/// Image block: thumbnail, full-screen preview, optional caption (PRD §4.3.3).
struct ImageBlockView: View {
    @Bindable var block: Block
    let onEdit: () -> Void

    @State private var showFullScreen = false
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

            TextField("添加图片说明(可选)", text: $block.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .onChange(of: block.caption) { _, _ in onEdit() }
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            if !block.imageRelativePath.isEmpty {
                ImageViewer(url: mediaStore.absoluteURL(for: block.imageRelativePath))
            }
        }
    }
}
