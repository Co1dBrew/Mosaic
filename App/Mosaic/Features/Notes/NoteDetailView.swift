import SwiftUI
import UIKit
import SwiftData
import PhotosUI
import MosaicKit

/// # 笔记页（`UI_REDESIGN.md` v2 §3）
///
/// v2 把原来的「卡片列表行里展开 AI 摘要」+「编辑器」两页合成一页。
/// 摘要与内容此前分居两处、永不同框；现在摘要是页面顶部一条 44pt 的横条。
///
/// ## 与旧 `CardEditorView` 的差别
///
/// | | 旧 | v2 |
/// |---|---|---|
/// | 摘要 | 列表行里展开 | 页面顶部横条，原地展开 |
/// | 低频动作 | 散落在 5 处 | 全部收进 `⋯` |
/// | 插入内容 | 「＋ 添加内容」菜单 | 底部常驻工具条，一次点击 |
/// | 文字块 | 每块一个「编辑/预览」按钮 | 零按钮，聚焦即源码 |
/// | 块的删除/排序 | swipe / EditButton / 无长按 | 长按菜单 + 拖拽 |
/// | 生成时机 | `onAppear` 生成 base、退出生成 update | **只有退出这一条规则** |
/// | 文件夹 | 改不了 | 导航栏 `📁 ▾` |
///
/// ## 保留不动的
///
/// 搜索落点（`SEARCH_CONTRACT.md` §3：滚动 · 高亮 · 可中断 · 转写先展开）
/// 原样搬过来。Goal 1 的 UI 行为**不允许因为换壳而回退**。
struct NoteDetailView: View {
    @Bindable var card: Card
    /// 从搜索结果进来时的落点。平时是 `nil` —— 那时既不滚动也不高亮。
    var landing: SearchAnchor?
    /// 这一次是不是「点新建」进来的。**只有它为真时**，退出时的空笔记才会被丢弃。
    ///
    /// 打开一条已有笔记、把内容删空、再退出 —— **不会**触发丢弃。
    /// 「清空」和「删除」是两个不同的意图，替用户做决定是越权；
    /// 何况删除入口本来就在 `⋯` 菜单里，一步可达。
    var isNewDraft: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.summaryService) private var summaryService
    @Environment(\.transcriptionService) private var transcriptionService
    @Environment(SettingsStore.self) private var settings
    @Environment(RetrievalEnvironment.self) private var retrieval: RetrievalEnvironment?
    @Query(sort: [SortDescriptor(\Folder.sortOrder), SortDescriptor(\Folder.createdAt)])
    private var folders: [Folder]

    @State private var player = AudioPlayerService()

    // 插入入口
    @State private var showRecorder = false
    @State private var showCamera = false
    @State private var showDocumentPicker = false
    @State private var showLinkPrompt = false
    @State private var linkText = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotosPicker = false
    @State private var pasteBanner: String?
    @State private var showNewFolderSheet = false
    @State private var showSettings = false

    // 摘要
    @State private var summaryExpanded = false
    @State private var isGeneratingSummary = false
    @State private var summaryError: String?
    @State private var summaryErrorIsConfig = false
    @State private var showPrivacyGate = false
    @State private var pendingPrivacyAction: (() -> Void)?
    @State private var showRegenerateConfirm = false
    @State private var showClearConfirm = false
    @State private var showDeleteConfirm = false

    // 转写
    @State private var transcribingBlockIDs: Set<UUID> = []
    @State private var transcriptionErrors: [UUID: String] = [:]
    @State private var showAudioUploadConsent = false
    @State private var pendingTranscribeBlockID: UUID?

    // 编辑
    @State private var focusedBlockID: UUID?
    @State private var showTagEditor = false
    @State private var banner: String?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var didDelete = false

    // 落点
    @State private var landingController = SearchLandingController()
    @State private var landingBlockHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    @Environment(\.dismiss) private var dismiss

    // MARK: 布局

    /// # 这一屏的笔记还在不在
    ///
    /// **SwiftData 里删掉的对象不能再读属性 —— 读一下就是 trap。**
    /// 真机实测（iPhone Air / iOS 27）：在笔记页删掉笔记，App 当场 crash，
    /// 栈是 `Card.tags.getter ← NoteDetailView.blockList ← body`，
    /// 底下是 SwiftData 的 `_assertionFailure`（`EXC_BREAKPOINT`）。
    ///
    /// 根因不是「删错了」，是**时序**：`dismiss()` 不是同步生效的。
    /// 从点下「删除」到这一屏真正消失之间，SwiftUI 至少还会重算一次 body，
    /// 而那次重算读的是一个已经不在上下文里的对象。
    /// 所以不能靠「删完就走」，得让 body 自己**不去读**。
    ///
    /// 两个条件各自独立：
    /// - `didDelete` —— 从这一屏删的。它在删除**之前**就置位（见 `deleteNote`）
    /// - `card.isDeleted` —— 从别处删的（删文件夹会连着删掉里面的笔记，
    ///   而这一屏可能正开着）。这条 `didDelete` 覆盖不到
    ///
    /// 模拟器上不复现。这是这一轮真机验证抓到的唯一一个产品缺陷。
    /// # 三个条件，缺一不可
    ///
    /// 修这个 crash 的时候错了两次，两次都值得记下来。
    ///
    /// **错误一：守卫放在 `body` 顶层。** 崩溃栈原样复现，只是多了一层
    /// `noteContent.getter`。原因是 SwiftUI 会直接重算 `GeometryReader` /
    /// `ScrollViewReader` / `List` 里那些**已经建好的内容闭包**，
    /// 不一定重新走一遍顶层 body。所以守卫必须放在**真正读 `card` 的那一层**。
    ///
    /// **错误二：以为 `card.isDeleted` 一直为真。** 实测不是
    /// （`ProductionSearchTests.testDeletionSignalsCoverBothWindows`）：
    ///
    /// | | `delete()` 之后 | `save()` 之后 |
    /// |---|---|---|
    /// | `isDeleted` | **true** | false |
    /// | `modelContext == nil` | false | **true** |
    ///
    /// 两个信号各自只覆盖一半窗口，**合起来才是完整的**。
    /// 两个都读得安全（不会 trap）—— 这一点本身有断言守着，
    /// 因为整道守卫都压在它上面：如果读一下就 trap，这道守卫等于不存在。
    ///
    /// `didDelete` 是第三条，覆盖「已标记但还没走到 `delete()`」那一小段。
    private var noteIsGone: Bool {
        didDelete || card.isDeleted || card.modelContext == nil
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    // 守卫放在**真正读 card 的那一层**，不是顶层 body。
                    // 放顶层挡不住 SwiftUI 对已建好的内容闭包的重算（见 `noteIsGone`）。
                    if noteIsGone {
                        // 退场中的这一屏渲染一个**完全不读 card** 的占位。
                        // 它只存在于「已经删了、还没 pop 完」那一两帧里。
                        Color.clear.accessibilityIdentifier("note.dismissing")
                    } else {
                        NoteSummaryBarView(state: summaryBarState,
                                           isExpanded: $summaryExpanded,
                                           summary: card.summary,
                                           onRetry: { gate { generateBase() } },
                                           onAddTopicAsTag: addTopicAsTag,
                                           onOpenSettings: { showSettings = true })
                        Divider()
                        blockList(proxy: proxy)
                    }
                }
                .onAppear { viewportHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, new in viewportHeight = new }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .navigationDestination(isPresented: $showSettings) { SettingsView() }
        .safeAreaInset(edge: .bottom) { insertToolbar }
        .modifier(NoteDetailSheets(
            card: card,
            showRecorder: $showRecorder, showCamera: $showCamera,
            showDocumentPicker: $showDocumentPicker, showPhotosPicker: $showPhotosPicker,
            photoItems: $photoItems, showShare: $showShare, shareItems: $shareItems,
            showTagEditor: $showTagEditor, showNewFolderSheet: $showNewFolderSheet,
            onAudio: addAudio, onImage: { addImage($0, source: .camera) },
            onDocument: addDocument, onPhotos: importPhotos,
            onTagChange: commitNow, onCreateFolder: createFolder))
        .modifier(NoteDetailDialogs(
            linkText: $linkText, showLinkPrompt: $showLinkPrompt,
            banner: $banner, pasteBanner: $pasteBanner,
            showPrivacyGate: $showPrivacyGate,
            showAudioUploadConsent: $showAudioUploadConsent,
            showRegenerateConfirm: $showRegenerateConfirm,
            showClearConfirm: $showClearConfirm,
            showDeleteConfirm: $showDeleteConfirm,
            onAddLink: addLink,
            onAcceptPrivacy: acceptPrivacy,
            onAcceptAudioUpload: acceptAudioUpload,
            onRegenerate: { gate { regenerate() } },
            onClear: clearSummary,
            onDelete: deleteNote))
        // §3.3「可中断」：用户滚动 / 点击 → 立即淡出高亮。
        .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in
            landingController.interrupt()
        })
        .simultaneousGesture(TapGesture().onEnded { landingController.interrupt() })
        .onAppear(perform: markUpdatesRead)
        .onDisappear(perform: handleExit)
    }

    private func blockList(proxy: ScrollViewProxy) -> some View {
        List {
            // 第二道。`List` 的 content 同样是个会被单独重算的闭包 ——
            // 崩溃栈里 `Section.init` 的上一帧就是它。
            if noteIsGone { EmptyView() } else {
            Section {
                TextField("标题（可留空，由 AI 生成）", text: $card.userTitle)
                    .font(.title3.bold())
                    .onChange(of: card.userTitle) { _, _ in scheduleAutosave() }
                    .accessibilityIdentifier("note.title")
                    .listRowSeparator(.hidden)

                // 标签：有才显示，点击展开编辑（§3.7）。无标签时靠底部 `#` 召唤。
                if !card.tags.isEmpty {
                    FlowLayout(spacing: AppSpacing.xs) {
                        ForEach(card.tags, id: \.self) { TagChip(text: $0) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showTagEditor = true }
                    .listRowSeparator(.hidden)
                }
            }

            Section {
                ForEach(card.orderedBlocks) { block in
                    blockRow(block)
                        .listRowSeparator(.hidden)
                        // IG-3：稳定唯一 id 是 Result → Note 的硬前置。
                        .id(block.id.uuidString)
                        .landingHighlight(isActive: landingController.isHighlighted(block.id.uuidString),
                                          opacity: landingController.highlightOpacity)
                        .background(landingMeasurement(for: block))
                        // §3.9：块的删除与排序统一为「长按菜单 + 拖拽」两条路径。
                        // 顶部的 EditButton 模式已删除。
                        .contextMenu { blockMenu(block) }
                }
                .onMove(perform: moveBlocks)
            }
            }   // if noteIsGone
        }
        .listStyle(.plain)
        .accessibilityIdentifier("note.blocks")
        .onAppear {
            ensureTrailingTextBlock(focusIfEmpty: true)
            performLanding(proxy: proxy)
        }
    }

    // MARK: 导航栏

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        // 中间：文件夹选择器（§3.2）。也是「移动到文件夹」的第二个入口 ——
        // 用户在写的过程中随手归类，而不是被迫在新建前就决定。
        ToolbarItem(placement: .principal) {
            Menu {
                Button { move(to: nil) } label: {
                    Label("未归类", systemImage: card.folder == nil ? "checkmark" : "tray")
                }
                ForEach(folders) { folder in
                    Button { move(to: folder) } label: {
                        Label(folder.name,
                              systemImage: card.folder?.id == folder.id ? "checkmark" : folder.iconName)
                    }
                }
                Divider()
                Button { showNewFolderSheet = true } label: { Label("新建文件夹…", systemImage: "folder.badge.plus") }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: card.folder?.iconName ?? "tray")
                        .font(.caption)
                    Text(card.folder?.name ?? "未归类")
                        .font(.subheadline)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .foregroundStyle(.primary)
            }
            .accessibilityIdentifier("note.folderPicker")
        }
        // 右：`⋯` —— 所有低频动作的唯一收口（§3.3）。
        // 之前它们散落在 5 处：pin 按钮、EditButton、底部 share 菜单、
        // 摘要贴纸里的三个按钮、两个 confirmationDialog。
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    card.isPinned.toggle()
                    try? modelContext.save()
                } label: {
                    Label(card.isPinned ? "取消置顶" : "置顶",
                          systemImage: card.isPinned ? "pin.slash" : "pin")
                }
                Divider()
                Button { gate { updateNow() } } label: { Label("立即更新总结", systemImage: "arrow.clockwise") }
                Button { showRegenerateConfirm = true } label: { Label("重新生成完整总结", systemImage: "sparkles") }
                if card.summary?.hasBase == true {
                    Button { showClearConfirm = true } label: { Label("清除 AI 摘要", systemImage: "eraser") }
                }
                Divider()
                ForEach(CardExportFormat.allCases, id: \.self) { format in
                    Button("导出为 \(format.displayName)") { export(format) }
                }
                Divider()
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("删除笔记", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("更多操作")
            .accessibilityIdentifier("note.more")
        }
    }

    // MARK: 底部工具条（§3.6）

    /// 取代旧的「＋ 添加内容」菜单。四个插入图标一次点击到位，
    /// 相机是唯一保留二级菜单的（真有两个来源）。
    private var insertToolbar: some View {
        VStack(spacing: 0) {
            if let pasteBanner {
                Text(pasteBanner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.xs)
            }
            Divider()
            HStack(spacing: 0) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Menu {
                        Button { showCamera = true } label: { Label("拍照", systemImage: "camera") }
                        Button { showPhotosPicker = true } label: { Label("从相册选", systemImage: "photo.on.rectangle") }
                    } label: {
                        toolbarIcon("camera")
                    }
                    .accessibilityLabel("插入图片")
                    .accessibilityIdentifier("note.insert.image")
                } else {
                    // 相机不可用时直接进相册，不弹一个只有一项的菜单。
                    Button { showPhotosPicker = true } label: { toolbarIcon("camera") }
                        .accessibilityLabel("插入图片")
                        .accessibilityIdentifier("note.insert.image")
                }
                Button { showRecorder = true } label: { toolbarIcon("mic") }
                    .accessibilityLabel("录音")
                    .accessibilityIdentifier("note.insert.audio")
                Button { showDocumentPicker = true } label: { toolbarIcon("doc") }
                    .accessibilityLabel("插入文档")
                    .accessibilityIdentifier("note.insert.file")
                Button { insertLinkFromPasteboardOrPrompt() } label: { toolbarIcon("link") }
                    .accessibilityLabel("插入链接")
                    .accessibilityIdentifier("note.insert.link")
                Spacer()
                Button { showTagEditor = true } label: { toolbarIcon("number") }
                    .accessibilityLabel("编辑标签")
                    .accessibilityIdentifier("note.insert.tag")
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(height: 48)
            .background(.bar)
        }
    }

    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 19))
            .frame(width: AppMetrics.minTapTarget, height: AppMetrics.minTapTarget)
            .contentShape(Rectangle())
    }

    // MARK: 摘要

    private var summaryBarState: NoteSummaryBarState {
        NoteSummaryPresentation.barState(
            hasBase: card.summary?.hasBase ?? false,
            oneLiner: card.summary?.baseOneLiner ?? "",
            noteIsEmpty: NoteListPresentation.isEmptyNote(card.blockContents()),
            isGenerating: isGeneratingSummary,
            errorMessage: summaryError,
            errorIsConfiguration: summaryErrorIsConfig,
            hasUnreadUpdates: (card.summary?.updateLogs ?? []).contains { !$0.isRead })
    }

    /// 进入笔记页即把更新记录标记为已读 —— 首页那个红点表达的是「有你没看过的更新」，
    /// 而人已经看到了。
    private func markUpdatesRead() {
        guard let logs = card.summary?.updateLogs, logs.contains(where: { !$0.isRead }) else { return }
        for log in logs where !log.isRead { log.isRead = true }
        try? modelContext.save()
    }

    private func addTopicAsTag(_ topic: String) {
        card.addTag(topic)
        try? modelContext.save()
    }

    // MARK: 块

    @ViewBuilder
    private func blockRow(_ block: Block) -> some View {
        switch block.kind {
        case .text:
            TextBlockView(block: block, onEdit: scheduleAutosave, focusedBlockID: $focusedBlockID)
        case .image:
            ImageBlockView(block: block, onEdit: scheduleAutosave)
        case .audio:
            AudioBlockView(
                block: block,
                player: player,
                isTranscribing: transcribingBlockIDs.contains(block.id),
                transcriptionError: transcriptionErrors[block.id],
                expandsTranscript: landingController.expandsTranscript(block.id.uuidString),
                onEdit: scheduleAutosave,
                onRetranscribe: { transcribe(block) }
            )
        case .file:
            FileBlockView(block: block)
        case .link:
            LinkBlockView(block: block, onEdit: scheduleAutosave)
        }
    }

    @ViewBuilder
    private func blockMenu(_ block: Block) -> some View {
        Button { moveBlock(block, by: -1) } label: { Label("上移", systemImage: "arrow.up") }
            .disabled(block.order == 0)
        Button { moveBlock(block, by: 1) } label: { Label("下移", systemImage: "arrow.down") }
            .disabled(block.order == card.orderedBlocks.count - 1)
        Divider()
        Button(role: .destructive) { deleteBlock(block) } label: { Label("删除", systemImage: "trash") }
    }

    // MARK: 落点（原样保留 SEARCH_CONTRACT §3）

    @ViewBuilder
    private func landingMeasurement(for block: Block) -> some View {
        if landing?.blockID == block.id.uuidString {
            GeometryReader { geo in
                Color.clear
                    .onAppear { landingBlockHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, new in landingBlockHeight = new }
            }
        }
    }

    private func performLanding(proxy: ScrollViewProxy) {
        guard let landing else { return }
        let existing = Set(card.orderedBlocks.map { $0.id.uuidString })
        landingController.land(anchor: landing, existingBlockIDs: existing) { blockID in
            switch SearchLanding.scrollTarget(blockHeight: Double(landingBlockHeight),
                                              viewportHeight: Double(viewportHeight)) {
            case .center:
                proxy.scrollTo(blockID, anchor: .center)
            case let .top(unitY):
                proxy.scrollTo(blockID, anchor: UnitPoint(x: 0.5, y: unitY))
            }
        }
    }

    // MARK: 编辑动作

    /// §3.5：**末尾永远有一个可写文字块**。删掉最后一个块时自动补一个空块，
    /// 因此「添加文字」这个动作在概念上被移除了。
    ///
    /// - Parameter focusIfEmpty: 卡片为空时把光标放进去（「进入即可写」）。
    ///   卡片非空时**不自动聚焦** —— 避免误改已有内容。
    private func ensureTrailingTextBlock(focusIfEmpty: Bool = false) {
        let blocks = card.orderedBlocks
        let wasEmpty = blocks.isEmpty
        if blocks.last?.kind != .text {
            let block = Block(kind: .text, order: card.nextBlockOrder)
            modelContext.insert(block)
            block.card = card
            if card.blocks == nil { card.blocks = [] }
            card.blocks?.append(block)
            try? modelContext.save()
            if focusIfEmpty && wasEmpty { focusedBlockID = block.id }
        }
    }

    /// 插入位置 = 当前光标所在块之后；无焦点时追加到末尾。
    /// 插入后自动在其下方补一个空文字块并聚焦 → 「插图 → 继续写」不中断。
    @discardableResult
    private func insertBlock(_ kind: BlockKind, configure: (Block) -> Void) -> Block {
        let anchorOrder = focusedBlockID.flatMap { id in
            card.orderedBlocks.first { $0.id == id }?.order
        } ?? (card.orderedBlocks.last?.order ?? -1)

        let block = Block(kind: kind, order: anchorOrder + 1)
        configure(block)
        modelContext.insert(block)
        block.card = card
        if card.blocks == nil { card.blocks = [] }
        card.blocks?.append(block)

        // 给后面的块让位。
        for other in card.orderedBlocks where other.id != block.id && other.order > anchorOrder {
            other.order += 1
        }
        block.order = anchorOrder + 1

        let follower = Block(kind: .text, order: block.order + 1)
        modelContext.insert(follower)
        follower.card = card
        card.blocks?.append(follower)
        for other in card.orderedBlocks where other.id != follower.id && other.order > block.order {
            other.order += 1
        }
        follower.order = block.order + 1

        commitNow()
        focusedBlockID = follower.id
        return block
    }

    private func moveBlock(_ block: Block, by offset: Int) {
        var ordered = card.orderedBlocks
        guard let index = ordered.firstIndex(where: { $0.id == block.id }) else { return }
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
        for (i, b) in ordered.enumerated() { b.order = i }
        commitNow()
    }

    private func moveBlocks(from source: IndexSet, to destination: Int) {
        var ordered = card.orderedBlocks
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, block) in ordered.enumerated() { block.order = index }
        commitNow()
    }

    private func deleteBlock(_ block: Block) {
        if focusedBlockID == block.id { focusedBlockID = nil }
        MediaStore.shared.deleteMedia(for: block)
        modelContext.delete(block)
        for (index, b) in card.orderedBlocks.enumerated() { b.order = index }
        commitNow()
        ensureTrailingTextBlock()
    }

    private func move(to folder: Folder?) {
        card.folder = folder
        card.touch()
        try? modelContext.save()
    }

    private func createFolder(_ result: FolderEditSheet.Result) {
        let folder = Folder(name: result.name, colorHex: result.colorHex,
                            iconName: result.iconName, sortOrder: result.sortOrder)
        modelContext.insert(folder)
        move(to: folder)
    }

    // MARK: 插入内容

    private func addImage(_ image: UIImage, source: ImageSource) {
        let pipeline = ImagePipeline()
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                try? pipeline.importImage(image)
            }.value
            guard let result else { banner = "图片处理失败，请重试。"; return }
            insertBlock(.image) { block in
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
        let block = insertBlock(.audio) { block in
            block.audioRelativePath = recording.relativePath
            block.durationSec = recording.duration
            block.waveformSamples = recording.waveform
        }
        transcribe(block)
    }

    private func addDocument(_ url: URL) {
        let importer = DocumentImporter()
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                try? importer.importDocument(from: url)
            }.value
            guard let result else { banner = "导入文档失败，请重试。"; return }
            insertBlock(.file) { block in
                block.fileRelativePath = result.relativePath
                block.fileName = result.fileName
                block.fileType = result.fileType
                block.extractedText = result.extractedText
                block.extractionUnavailable = result.extractionUnavailable
            }
        }
    }

    /// §3.6：**剪贴板是 URL 时直接插入**并显示「已粘贴 example.com」，否则弹输入框。
    /// 大多数链接就是刚复制的那一个 —— 让用户再粘贴一次是多余的一步。
    private func insertLinkFromPasteboardOrPrompt() {
        if let url = UIPasteboard.general.url ?? pasteboardURL() {
            insertBlock(.link) { $0.url = url.absoluteString }
            pasteBanner = "已粘贴 \(url.host() ?? url.absoluteString)"
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                pasteBanner = nil
            }
        } else {
            showLinkPrompt = true
        }
    }

    private func pasteboardURL() -> URL? {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://"),
              let url = URL(string: text) else { return nil }
        return url
    }

    private func addLink(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        insertBlock(.link) { $0.url = trimmed }
    }

    // MARK: 转写

    private func transcribe(_ block: Block) {
        guard !block.audioRelativePath.isEmpty, let service = transcriptionService else { return }
        if service.needsAudioUploadConsent {
            pendingTranscribeBlockID = block.id
            showAudioUploadConsent = true
            return
        }
        runTranscription(block)
    }

    private func acceptAudioUpload() {
        settings.hasAcceptedAudioUploadNotice = true
        if let id = pendingTranscribeBlockID,
           let block = card.orderedBlocks.first(where: { $0.id == id }) {
            runTranscription(block)
        }
        pendingTranscribeBlockID = nil
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

    // MARK: 摘要动作

    /// 首次 AI 隐私同意的闸门。**内容不能在同意之前离开设备。**
    private func gate(_ action: @escaping () -> Void) {
        if settings.hasAcceptedAIPrivacyNotice { action() }
        else { pendingPrivacyAction = action; showPrivacyGate = true }
    }

    private func acceptPrivacy() {
        settings.hasAcceptedAIPrivacyNotice = true
        let action = pendingPrivacyAction
        pendingPrivacyAction = nil
        action?()
    }

    private func generateBase() {
        runSummary { try await summaryService?.generateBaseSummary(for: card) }
    }

    private func updateNow() {
        runSummary { _ = try await summaryService?.generateUpdateSummary(for: card, force: true) }
    }

    private func regenerate() {
        runSummary { try await summaryService?.regenerateFullSummary(for: card) }
    }

    private func clearSummary() {
        summaryService?.clearSummary(for: card)
        summaryError = nil
    }

    private func runSummary(_ work: @escaping () async throws -> Void) {
        commitNow()
        isGeneratingSummary = true
        summaryError = nil
        Task { @MainActor in
            defer { isGeneratingSummary = false }
            do { try await work() }
            catch let error as AIError {
                summaryError = error.userMessage
                summaryErrorIsConfig = error.isConfiguration
            }
            catch { summaryError = error.localizedDescription; summaryErrorIsConfig = false }
        }
    }

    // MARK: 导出 / 删除

    private func export(_ format: CardExportFormat) {
        commitNow()
        do {
            shareItems = [try CardExportService.writeTempFile(for: card, format: format)]
            showShare = true
        } catch {
            banner = "导出失败，请重试。"
        }
    }

    private func deleteNote() {
        let noteID = card.id.uuidString
        // **先标记，再删。**
        //
        // 这一行原来在最后。顺序反过来的代价是一次真机 crash：
        // `modelContext.delete` 之后、`dismiss()` 生效之前，body 还会重算一次，
        // 读到 `card.tags` 就 trap（见 `noteIsGone` 上的说明）。
        // 先置位，body 从这一刻起走占位分支，不再碰这个对象。
        //
        // 它同时是 `handleExit` 的闸门：退场时不该再对一个已删除的对象做任何事。
        didDelete = true
        for block in card.blocks ?? [] { MediaStore.shared.deleteMedia(for: block) }
        modelContext.delete(card)
        try? modelContext.save()
        // derived 数据在另一个 container 里，没有 cascade 能到达它。
        if let retrieval {
            Task { await retrieval.noteWasDeleted(noteID) }
        }
        dismiss()
    }

    // MARK: 持久化 / 退出

    private func scheduleAutosave() {
        landingController.interrupt()
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            commitNow()
        }
    }

    private func commitNow() {
        guard !didDelete else { return }
        card.touch()
        try? modelContext.save()
        // 保存之后才通知索引 —— 索引读的是 SwiftData 里的权威内容。
        retrieval?.noteDidChange(card.id.uuidString)
    }

    /// 退出（§3.10）：flush → 清理空块 → 按**一条规则**决定生成什么。
    ///
    /// 判定在内核 `SummaryOnExit.action(...)`，因为它是产品规则不是 UI 细节：
    /// 「写完退出，AI 就会总结」。旧版有两套机制（首次展开小三角生成初始总结 /
    /// 退出时生成更新记录），用户要理解两条规则才知道什么时候会花钱。
    private func handleExit() {
        guard !didDelete else { return }
        autosaveTask?.cancel()
        cleanupEmptyBlocks()
        commitNow()

        // 什么都没写就离开的新建草稿 → **不留下任何东西**。
        // 放在 `commitNow()` 之后：判定要基于落盘后的真实内容，
        // 而不是内存里可能还没提交的那一份。
        if discardEmptyDraftIfNeeded() { return }

        let action = SummaryOnExit.action(
            autoUpdateEnabled: settings.autoUpdateSummary,
            privacyAccepted: settings.hasAcceptedAIPrivacyNotice,
            hasBase: card.summary?.hasBase ?? false,
            hasContent: !NoteListPresentation.isEmptyNote(card.blockContents()),
            hasPendingChanges: summaryService?.hasPendingChanges(for: card) ?? false)

        guard let summaryService else { return }
        switch action {
        case .none:
            break
        case .generateBase:
            Task { @MainActor in try? await summaryService.generateBaseSummary(for: card) }
        case .appendUpdate:
            Task { @MainActor in _ = try? await summaryService.generateUpdateSummary(for: card, force: false) }
        }
    }

    /// 空文字块在退出时清理，不留脏数据。**保留最后一个** —— 下次进来时
    /// 「末尾永远有一个可写文字块」还得靠它，而且笔记完全为空时也需要它。
    /// # 空白新建草稿的丢弃
    ///
    /// 点「新建」只表达一次**创建意图**，不等于数据库里已经有了一条永久笔记。
    /// 在这条规则之前，每一次误触悬浮按钮都会在笔记流里留下一行「未命名笔记」——
    /// 一个由 App 制造、却要用户自己去长按删除的烂摊子。
    ///
    /// ## 为什么是「先建后删」而不是「延迟落盘」
    ///
    /// 延迟落盘（草稿态编辑器，有内容才 insert）是更干净的架构，但它要动的是
    /// `@Bindable var card: Card`、`AppRoute` 持有的对象、以及每一个内容块的
    /// `modelContext` 写入路径 —— 在收口阶段做这件事，风险远大于收益。
    /// 「建了再删」是产品语义相同、改动面小得多的等价实现，
    /// **前提是清理必须完整**（见下）。
    ///
    /// ## 清理必须完整
    ///
    /// 走的是**删除笔记那条既有路径**，不是新写一遍：
    /// `MediaStore` 的媒体文件 → SwiftData 的 Card（级联删块）→
    /// `retrieval.noteWasDeleted` 清 derived（chunk / OCR / 内存向量索引）。
    ///
    /// 复用而不是重写，是因为这条路径正是上一轮修 D1（删文件夹的 derived 泄漏）时
    /// 收口过的那一条。**再写一遍就等于再制造一次 orphan derived data。**
    ///
    /// - Returns: 真的丢弃了返回 `true`，调用方据此跳过后面的总结生成 ——
    ///   给一条刚被删掉的笔记生成摘要既花钱又毫无意义。
    @discardableResult
    private func discardEmptyDraftIfNeeded() -> Bool {
        // **`onDisappear` 不等于「这一屏走了」。**
        //
        // 在 `NavigationStack` 里，往上推一屏（这里唯一的一处是笔记页 →「设置」）
        // 同样会让当前这屏收到 `onDisappear`。那一刻笔记还在栈里、用户马上会回来 ——
        // 此时删掉它，用户返回时会看到一个空壳。
        //
        // 摘要生成走这条路只是白花一次钱；**删除走这条路是丢数据**，
        // 所以这一条必须显式挡住。判据用「有没有往上推」而不是别的：
        // 它就是那个区别本身。
        guard !showSettings else { return false }

        guard NoteDraftPolicy.shouldDiscardOnExit(isNewDraft: isNewDraft,
                                                  title: card.userTitle,
                                                  tags: card.tags,
                                                  blocks: card.blockContents(),
                                                  derivedTexts: derivedTextsForDraftCheck())
        else { return false }

        let noteID = card.id.uuidString
        didDelete = true
        for block in card.blocks ?? [] { MediaStore.shared.deleteMedia(for: block) }
        modelContext.delete(card)
        try? modelContext.save()
        if let retrieval {
            Task { await retrieval.noteWasDeleted(noteID) }
        }
        return true
    }

    /// OCR / 转写这类**衍生**文本。
    ///
    /// 它们不是用户直接输入的，所以是兜底而不是主判据 —— 有 OCR 就一定有图片块，
    /// 而图片块本身已经被 `blockContents()` 判到了。留着它是为了防一种情况：
    /// 媒体文件因为某种原因丢了引用，但识别出来的文字还在。
    /// 那时这条笔记里仍然有用户能搜到的东西，不该被当成空的删掉。
    private func derivedTextsForDraftCheck() -> [String] {
        guard let retrieval else { return [] }
        let ocr = retrieval.derived.ocrTextByBlockID(noteID: card.id.uuidString)
        return Array(ocr.values) + (card.blocks ?? []).compactMap { $0.transcript }
    }

    private func cleanupEmptyBlocks() {
        let ordered = card.orderedBlocks
        let empties = ordered.filter { $0.isEffectivelyEmpty }
        guard !empties.isEmpty else { return }
        // 全空 → 一个都不删（这是一条空笔记，用户可能马上回来写）。
        let keepLast = empties.count == ordered.count
        for (i, block) in empties.enumerated() {
            if keepLast && i == empties.count - 1 { continue }
            MediaStore.shared.deleteMedia(for: block)
            modelContext.delete(block)
        }
        for (index, block) in card.orderedBlocks.enumerated() { block.order = index }
    }
}
