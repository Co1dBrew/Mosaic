import SwiftUI
import UIKit
import SwiftData
import PhotosUI
import MosaicKit

/// The card editor (PRD §4.3): a block-based linear document with add / delete /
/// reorder, autosave, offline editing, and auto-update-summary on exit.
struct CardEditorView: View {
    @Bindable var card: Card

    @Environment(\.modelContext) private var modelContext
    @Environment(\.summaryService) private var summaryService
    @Environment(\.transcriptionService) private var transcriptionService
    @Environment(SettingsStore.self) private var settings

    @State private var player = AudioPlayerService()

    @State private var showRecorder = false
    @State private var showCamera = false
    @State private var showDocumentPicker = false
    @State private var showLinkPrompt = false
    @State private var linkText = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotosPicker = false

    @State private var transcribingBlockIDs: Set<UUID> = []
    @State private var transcriptionErrors: [UUID: String] = [:]
    @State private var showAudioUploadConsent = false
    @State private var pendingTranscribeBlockID: UUID?
    @State private var banner: String?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var shareItems: [Any] = []
    @State private var showShare = false

    var body: some View {
        List {
            Section {
                TextField("标题(可留空,由 AI 生成)", text: $card.userTitle)
                    .font(.title3.bold())
                    .onChange(of: card.userTitle) { _, _ in scheduleAutosave() }
            }

            Section("标签") {
                TagEditorView(card: card, onChange: commitNow)
            }

            Section {
                if card.orderedBlocks.isEmpty {
                    Text("点击下方「添加内容」,把文字、录音、图片、文档、链接塞进这张卡片。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(card.orderedBlocks) { block in
                        blockRow(block)
                            .listRowSeparator(.hidden)
                    }
                    .onMove(perform: moveBlocks)
                    .onDelete(perform: deleteBlocks)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(card.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    card.isPinned.toggle()
                    try? modelContext.save()
                } label: {
                    Image(systemName: card.isPinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel(card.isPinned ? "取消置顶" : "置顶")
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItemGroup(placement: .bottomBar) {
                addContentMenu
                Spacer()
                shareMenu
            }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $photoItems, maxSelectionCount: 9, matching: .images)
        .onChange(of: photoItems) { _, items in if !items.isEmpty { importPhotos(items) } }
        .sheet(isPresented: $showRecorder) {
            AudioRecorderSheet { recording in addAudio(recording) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in addImage(image, source: .camera) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url in addDocument(url) }
        }
        .alert("添加链接", isPresented: $showLinkPrompt) {
            TextField("https://", text: $linkText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("取消", role: .cancel) { linkText = "" }
            Button("添加") { addLink(linkText); linkText = "" }
        }
        .alert("提示", isPresented: Binding(get: { banner != nil }, set: { if !$0 { banner = nil } })) {
            Button("好") { banner = nil }
        } message: { Text(banner ?? "") }
        .alert("上传音频以进行云端转写", isPresented: $showAudioUploadConsent) {
            Button("取消", role: .cancel) { pendingTranscribeBlockID = nil }
            Button("同意并上传") {
                settings.hasAcceptedAudioUploadNotice = true
                if let id = pendingTranscribeBlockID,
                   let block = card.orderedBlocks.first(where: { $0.id == id }) {
                    runTranscription(block)
                }
                pendingTranscribeBlockID = nil
            }
        } message: {
            Text("你选择了「API 云端转写」。这会把这段录音的音频文件通过 HTTPS 上传到你在「设置」中配置的第三方服务进行识别。若不希望上传音频,可在「设置」改用「Apple 本地转写」(不上传音频)。")
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
        .onDisappear(perform: handleExit)
    }

    private var shareMenu: some View {
        Menu {
            ForEach(CardExportFormat.allCases, id: \.self) { format in
                Button("导出为 \(format.displayName)") { export(format) }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }

    private func export(_ format: CardExportFormat) {
        commitNow() // flush pending edits so the export is current
        do {
            let url = try CardExportService.writeTempFile(for: card, format: format)
            shareItems = [url]
            showShare = true
        } catch {
            banner = "导出失败,请重试。"
        }
    }

    // MARK: Block rendering

    @ViewBuilder
    private func blockRow(_ block: Block) -> some View {
        switch block.kind {
        case .text:
            TextBlockView(block: block, onEdit: scheduleAutosave)
        case .image:
            ImageBlockView(block: block, onEdit: scheduleAutosave)
        case .audio:
            AudioBlockView(
                block: block,
                player: player,
                isTranscribing: transcribingBlockIDs.contains(block.id),
                transcriptionError: transcriptionErrors[block.id],
                onEdit: scheduleAutosave,
                onRetranscribe: { transcribe(block) }
            )
        case .file:
            FileBlockView(block: block)
        case .link:
            LinkBlockView(block: block, onEdit: scheduleAutosave)
        }
    }

    private var addContentMenu: some View {
        Menu {
            Button { addText() } label: { Label("文字", systemImage: "text.alignleft") }
            Button { showPhotosPicker = true } label: { Label("从相册选图", systemImage: "photo.on.rectangle") }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label("拍照", systemImage: "camera") }
            }
            Button { showRecorder = true } label: { Label("录音", systemImage: "mic") }
            Button { showDocumentPicker = true } label: { Label("导入文档", systemImage: "doc") }
            Button { showLinkPrompt = true } label: { Label("添加链接", systemImage: "link") }
        } label: {
            Label("添加内容", systemImage: "plus.circle.fill")
                .font(.body.bold())
        }
    }

    // MARK: Adders

    private func appendBlock(_ kind: BlockKind, configure: (Block) -> Void) {
        let block = Block(kind: kind, order: card.nextBlockOrder)
        configure(block)
        modelContext.insert(block)
        block.card = card
        if card.blocks == nil { card.blocks = [] }
        card.blocks?.append(block)
        commitNow()
    }

    private func addText() {
        appendBlock(.text) { _ in }
    }

    private func addImage(_ image: UIImage, source: ImageSource) {
        let pipeline = ImagePipeline()
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                try? pipeline.importImage(image)
            }.value
            guard let result else { banner = "图片处理失败,请重试。"; return }
            appendBlock(.image) { block in
                block.imageRelativePath = result.imageRelativePath
                block.thumbnailRelativePath = result.thumbnailRelativePath
                block.imageSourceRaw = source.rawValue
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        let captured = items
        photoItems = []
        Task { @MainActor in
            for item in captured {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    addImage(image, source: .library)
                }
            }
        }
    }

    private func addAudio(_ recording: AudioRecorderService.Recording) {
        appendBlock(.audio) { block in
            block.audioRelativePath = recording.relativePath
            block.durationSec = recording.duration
            block.waveformSamples = recording.waveform
        }
        // Transcribe the most recently added audio block.
        if let block = card.orderedBlocks.last(where: { $0.audioRelativePath == recording.relativePath }) {
            transcribe(block)
        }
    }

    private func transcribe(_ block: Block) {
        guard !block.audioRelativePath.isEmpty, let service = transcriptionService else { return }
        // Cloud mode uploads audio — require explicit consent first (PRD privacy).
        if service.needsAudioUploadConsent {
            pendingTranscribeBlockID = block.id
            showAudioUploadConsent = true
            return
        }
        runTranscription(block)
    }

    private func runTranscription(_ block: Block) {
        guard let service = transcriptionService else { return }
        transcribingBlockIDs.insert(block.id)
        transcriptionErrors[block.id] = nil
        let path = block.audioRelativePath
        Task { @MainActor in
            defer { transcribingBlockIDs.remove(block.id) }
            do {
                let text = try await service.transcribe(relativePath: path)
                block.transcript = text
                commitNow()
            } catch let error as TranscriptionError {
                transcriptionErrors[block.id] = error.userMessage
            } catch {
                transcriptionErrors[block.id] = error.localizedDescription
            }
        }
    }

    private func addDocument(_ url: URL) {
        let importer = DocumentImporter()
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                try? importer.importDocument(from: url)
            }.value
            guard let result else { banner = "导入文档失败,请重试。"; return }
            appendBlock(.file) { block in
                block.fileRelativePath = result.relativePath
                block.fileName = result.fileName
                block.fileType = result.fileType
                block.extractedText = result.extractedText
                block.extractionUnavailable = result.extractionUnavailable
            }
        }
    }

    private func addLink(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendBlock(.link) { block in block.url = trimmed }
    }

    // MARK: Reorder / delete

    private func moveBlocks(from source: IndexSet, to destination: Int) {
        var ordered = card.orderedBlocks
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, block) in ordered.enumerated() { block.order = index }
        commitNow()
    }

    private func deleteBlocks(at offsets: IndexSet) {
        let ordered = card.orderedBlocks
        for index in offsets {
            let block = ordered[index]
            MediaStore.shared.deleteMedia(for: block)
            modelContext.delete(block)
        }
        // Reassign contiguous order indices.
        for (index, block) in card.orderedBlocks.enumerated() { block.order = index }
        commitNow()
    }

    // MARK: Persistence / exit

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            commitNow()
        }
    }

    private func commitNow() {
        card.touch()
        try? modelContext.save()
    }

    /// On leaving the editor: flush autosave and auto-generate an update summary
    /// if enabled and there are significant pending changes (PRD §4.5 debounce on exit).
    private func handleExit() {
        autosaveTask?.cancel()
        commitNow()
        // Auto-update is an AI network call, so it must respect privacy consent
        // (PRD §6.1) — never send content before the user has accepted.
        guard settings.autoUpdateSummary,
              settings.hasAcceptedAIPrivacyNotice,
              let summaryService,
              card.summary?.hasBase == true,
              summaryService.hasPendingChanges(for: card) else { return }
        Task { @MainActor in try? await summaryService.generateUpdateSummary(for: card, force: false) }
    }
}
