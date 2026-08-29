import SwiftUI
import UIKit

/// 链接块（PRD §4.3.5 · `UI_REDESIGN.md` v2 §3.8）。
///
/// v2 去掉了卡片下方那个**常驻的「编辑网址」输入框** —— 它与卡片里显示的网址是
/// 同一份信息的两份拷贝，而编辑网址是极低频的动作。改到长按菜单里。
struct LinkBlockView: View {
    @Bindable var block: Block
    let onEdit: () -> Void

    @State private var showSafari = false
    @State private var showURLEditor = false
    @State private var draftURL = ""

    private var normalizedURL: URL? {
        var s = block.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        return URL(string: s)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                if !block.linkTitle.isEmpty {
                    Text(block.linkTitle).font(.subheadline).bold().lineLimit(1)
                }
                Text(block.url.isEmpty ? "未填写网址" : block.url)
                    .font(.caption)
                    .foregroundStyle(block.url.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            if normalizedURL != nil {
                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            if normalizedURL != nil { showSafari = true } else { beginEditingURL() }
        }
        .contextMenu {
            if let url = normalizedURL {
                Button { UIApplication.shared.open(url) } label: { Label("用 Safari 打开", systemImage: "safari") }
                Button { UIPasteboard.general.string = url.absoluteString } label: { Label("复制链接", systemImage: "doc.on.doc") }
            }
            Button { beginEditingURL() } label: { Label("编辑网址", systemImage: "pencil") }
        }
        .alert("编辑网址", isPresented: $showURLEditor) {
            TextField("https://", text: $draftURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("取消", role: .cancel) { }
            Button("保存") {
                block.url = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                onEdit()
            }
        }
        .sheet(isPresented: $showSafari) {
            if let url = normalizedURL { SafariView(url: url).ignoresSafeArea() }
        }
        .accessibilityIdentifier("block.link.\(block.id.uuidString)")
    }

    private func beginEditingURL() {
        draftURL = block.url
        showURLEditor = true
    }
}
