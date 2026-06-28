import SwiftUI
import UIKit

/// Document block: icon + name + type, QuickLook preview, and a clear marker
/// when text extraction is unavailable (PRD §4.3.4).
struct FileBlockView: View {
    let block: Block
    @State private var showPreview = false
    private let mediaStore = MediaStore.shared

    var body: some View {
        Button {
            if mediaStore.fileExists(block.fileRelativePath) { showPreview = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(block.fileName.isEmpty ? "文档" : block.fileName)
                        .font(.subheadline).bold()
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(block.fileType.isEmpty ? "文件" : block.fileType)
                            .font(.caption).foregroundStyle(.secondary)
                        if block.extractionUnavailable {
                            Text("· 暂不支持提取文字")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPreview) {
            QuickLookView(url: mediaStore.absoluteURL(for: block.fileRelativePath))
                .ignoresSafeArea()
        }
    }
}
