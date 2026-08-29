import SwiftUI
import PhotosUI
import MosaicKit

/// 笔记页的 sheet / fullScreenCover 集合。
///
/// 单独拆出来只有一个原因：`NoteDetailView.body` 上挂十几个修饰符时，
/// SwiftUI 的类型检查会退化成分钟级的编译（实测），而且报错信息会指到一个
/// 与真正问题无关的位置。拆成两个 `ViewModifier` 之后每一块都能独立类型检查。
struct NoteDetailSheets: ViewModifier {
    let card: Card

    @Binding var showRecorder: Bool
    @Binding var showCamera: Bool
    @Binding var showDocumentPicker: Bool
    @Binding var showPhotosPicker: Bool
    @Binding var photoItems: [PhotosPickerItem]
    @Binding var showShare: Bool
    @Binding var shareItems: [Any]
    @Binding var showTagEditor: Bool
    @Binding var showNewFolderSheet: Bool

    let onAudio: (AudioRecorderService.Recording) -> Void
    let onImage: (UIImage) -> Void
    let onDocument: (URL) -> Void
    let onPhotos: ([PhotosPickerItem]) -> Void
    let onTagChange: () -> Void
    let onCreateFolder: (FolderEditSheet.Result) -> Void

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showPhotosPicker, selection: $photoItems,
                          maxSelectionCount: 9, matching: .images)
            .onChange(of: photoItems) { _, items in if !items.isEmpty { onPhotos(items) } }
            .sheet(isPresented: $showRecorder) {
                AudioRecorderSheet { onAudio($0) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { onImage($0) }.ignoresSafeArea()
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { onDocument($0) }
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showTagEditor) {
                NavigationStack {
                    Form {
                        TagEditorView(card: card, onChange: onTagChange)
                    }
                    .navigationTitle("标签")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showTagEditor = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showNewFolderSheet) {
                FolderEditSheet(folder: nil, nextSortOrder: 0) { onCreateFolder($0) }
            }
    }
}

/// 笔记页的 alert / confirmationDialog 集合。见 `NoteDetailSheets` 的拆分理由。
struct NoteDetailDialogs: ViewModifier {
    @Binding var linkText: String
    @Binding var showLinkPrompt: Bool
    @Binding var banner: String?
    @Binding var pasteBanner: String?
    @Binding var showPrivacyGate: Bool
    @Binding var showAudioUploadConsent: Bool
    @Binding var showRegenerateConfirm: Bool
    @Binding var showClearConfirm: Bool
    @Binding var showDeleteConfirm: Bool

    let onAddLink: (String) -> Void
    let onAcceptPrivacy: () -> Void
    let onAcceptAudioUpload: () -> Void
    let onRegenerate: () -> Void
    let onClear: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("添加链接", isPresented: $showLinkPrompt) {
                TextField("https://", text: $linkText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("取消", role: .cancel) { linkText = "" }
                Button("添加") { onAddLink(linkText); linkText = "" }
            }
            .alert("提示", isPresented: Binding(get: { banner != nil },
                                             set: { if !$0 { banner = nil } })) {
                Button("好") { banner = nil }
            } message: { Text(banner ?? "") }
            .alert("隐私提示", isPresented: $showPrivacyGate) {
                Button("取消", role: .cancel) { }
                Button("同意并继续") { onAcceptPrivacy() }
            } message: {
                Text("生成总结会把这张笔记的文字内容与图片，通过 HTTPS 发送到你在「设置」中选择的第三方 AI 服务商。原始录音不会上传（改用本地转写文字）。调用费用由你的 API Key 账户承担。")
            }
            .alert("上传音频以进行云端转写", isPresented: $showAudioUploadConsent) {
                Button("取消", role: .cancel) { }
                Button("同意并上传") { onAcceptAudioUpload() }
            } message: {
                Text("你选择了「API 云端转写」。这会把这段录音的音频文件通过 HTTPS 上传到你在「设置」中配置的第三方服务进行识别。若不希望上传音频，可在「设置」改用「Apple 本地转写」（不上传音频）。")
            }
            .confirmationDialog("重新生成完整总结？", isPresented: $showRegenerateConfirm,
                                titleVisibility: .visible) {
                Button("重新生成", role: .destructive) { onRegenerate() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("将清空当前的初始总结与全部更新记录，并重新生成。")
            }
            .confirmationDialog("清除这条笔记的 AI 摘要？", isPresented: $showClearConfirm,
                                titleVisibility: .visible) {
                Button("清除", role: .destructive) { onClear() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("将删除初始总结与全部更新记录（不会重新生成），不影响笔记内容。")
            }
            .confirmationDialog("删除这条笔记？", isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("删除", role: .destructive) { onDelete() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("此操作不可撤销。")
            }
    }
}
