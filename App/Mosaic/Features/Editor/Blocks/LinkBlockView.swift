import SwiftUI
import UIKit

/// Link block: stores a URL, opens it in-app, with copy / open-in-Safari menu
/// (PRD §4.3.5). MVP shows URL + optional title.
struct LinkBlockView: View {
    @Bindable var block: Block
    let onEdit: () -> Void

    @State private var showSafari = false

    private var normalizedURL: URL? {
        var s = block.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        return URL(string: s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .contentShape(Rectangle())
            .onTapGesture { if normalizedURL != nil { showSafari = true } }
            .contextMenu {
                if let url = normalizedURL {
                    Button { UIApplication.shared.open(url) } label: { Label("用 Safari 打开", systemImage: "safari") }
                    Button { UIPasteboard.general.string = url.absoluteString } label: { Label("复制链接", systemImage: "doc.on.doc") }
                }
            }

            TextField("编辑网址", text: $block.url)
                .font(.caption)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .onChange(of: block.url) { _, _ in onEdit() }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $showSafari) {
            if let url = normalizedURL { SafariView(url: url).ignoresSafeArea() }
        }
    }
}
