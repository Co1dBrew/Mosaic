import SwiftUI
import SwiftData
import MosaicKit

/// # 首页「全部笔记」（`UI_REDESIGN.md` v2 §2）
///
/// 这是 v2 的根页面，取代原来的 `FolderListView` → `CardListView` 两级。
/// 层级从 3 级（文件夹 → 卡片 → 编辑器）降到 **2 级**（笔记流 → 笔记页）。
///
/// 文件夹没有被删掉，它降级为**筛选**：一行横向 chip。「未归类」用
/// `folder == nil` 表达，不建实体行 —— 它因此天然不可重命名、不可删除。
///
/// 取值规则（第二行三级回退、chip 行构成、标题）都在内核
/// `NoteListPresentation` / `FolderChipBar` 里，可断言。这里只负责画。
struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RetrievalEnvironment.self) private var retrieval: RetrievalEnvironment?
    @Environment(AppRouter.self) private var router

    /// 全库笔记。排序在 `CardSorting` 里（置顶优先 → updatedAt 倒序），
    /// 不用 `@Query` 的 sort —— 两处排序迟早会不一致。
    @Query private var allCards: [Card]
    @Query(sort: [SortDescriptor(\Folder.sortOrder), SortDescriptor(\Folder.createdAt)])
    private var folders: [Folder]

    @State private var filter: NoteFilter = .all
    @State private var cardToDelete: Card?
    @State private var movingCard: Card?
    @State private var shareItems: [Any] = []
    @State private var showShare = false

    // MARK: 数据

    private var chipSources: [FolderChipSource] {
        folders.map { FolderChipSource(id: $0.id.uuidString, name: $0.name,
                                       colorHex: $0.colorHex, iconName: $0.iconName) }
    }

    private var hasUnfiledNotes: Bool { allCards.contains { $0.folder == nil } }

    private var chips: [FolderChip] {
        FolderChipBar.chips(folders: chipSources, hasUnfiledNotes: hasUnfiledNotes)
    }

    private var visibleCards: [Card] {
        let filtered: [Card]
        switch filter {
        case .all:
            filtered = allCards
        case .unfiled:
            filtered = allCards.filter { $0.folder == nil }
        case .folder(let id):
            filtered = allCards.filter { $0.folder?.id.uuidString == id }
        }
        return filtered.sorted { lhs, rhs in
            CardSorting.isOrderedBefore(
                CardSortKey(id: lhs.id.uuidString, isPinned: lhs.isPinned, updatedAt: lhs.updatedAt),
                CardSortKey(id: rhs.id.uuidString, isPinned: rhs.isPinned, updatedAt: rhs.updatedAt))
        }
    }

    // MARK: 布局

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                if !chips.isEmpty {
                    FolderChipRow(chips: chips, selected: filter,
                                  onSelect: select, onManage: { router.push(.folders) })
                    Divider()
                }
                content
            }
            composeButton
        }
        .navigationTitle(FolderChipBar.title(for: filter, folders: chipSources))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { router.push(.settings) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("设置")
                    .accessibilityIdentifier("notes.settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.search) } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("搜索")
                    .accessibilityIdentifier("notes.search")
            }
        }
        .sheet(item: $movingCard) { card in
            MoveToFolderSheet(card: card, folders: folders) { commit() }
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        .alert("删除笔记", isPresented: Binding(get: { cardToDelete != nil },
                                            set: { if !$0 { cardToDelete = nil } })) {
            Button("取消", role: .cancel) { cardToDelete = nil }
            Button("删除", role: .destructive) {
                if let card = cardToDelete { delete(card) }
                cardToDelete = nil
            }
        } message: {
            Text("此操作不可撤销。")
        }
        // 筛选中的文件夹被删掉时回到「全部」—— 否则会停在一个空列表上，
        // 而那个空列表的空状态说的是「这个文件夹还是空的」，是错的。
        .onChange(of: folders.count) { _, _ in
            if case .folder(let id) = filter, !folders.contains(where: { $0.id.uuidString == id }) {
                filter = .all
            }
        }
    }

    @ViewBuilder private var content: some View {
        if visibleCards.isEmpty {
            emptyState
        } else {
            List {
                ForEach(visibleCards) { card in
                    // **整行是单一点击区**（§2.3）。用 `Button` 而不是
                    // `.onTapGesture`：实测在 `List` 行上后者不触发。
                    // 也不用 `NavigationLink` —— 它会带回那个设计明确要求删掉的 chevron。
                    Button { router.push(.note(card: card, anchor: nil)) } label: {
                        NoteRowView(card: card)
                    }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .swipeActions(edge: .leading) {
                            Button { togglePin(card) } label: {
                                Label(card.isPinned ? "取消置顶" : "置顶",
                                      systemImage: card.isPinned ? "pin.slash" : "pin")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { cardToDelete = card } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .contextMenu { rowMenu(card) }
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("notes.list")
        }
    }

    @ViewBuilder private func rowMenu(_ card: Card) -> some View {
        Button {
            togglePin(card)
        } label: {
            Label(card.isPinned ? "取消置顶" : "置顶", systemImage: card.isPinned ? "pin.slash" : "pin")
        }
        Button { movingCard = card } label: { Label("移动到文件夹…", systemImage: "folder") }
        Menu {
            ForEach(CardExportFormat.allCases, id: \.self) { format in
                Button("导出为 \(format.displayName)") { export(card, format) }
            }
        } label: {
            Label("分享 / 导出…", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button(role: .destructive) { cardToDelete = card } label: {
            Label("删除", systemImage: "trash")
        }
    }

    @ViewBuilder private var emptyState: some View {
        switch filter {
        case .all:
            EmptyStateView(icon: "square.and.pencil",
                           title: "还没有笔记",
                           message: "点右下角 ✎ 写下第一条，文字、录音、图片、文档、链接都能塞进来。")
                .accessibilityIdentifier("notes.empty.all")
        case .unfiled:
            EmptyStateView(icon: "tray",
                           title: "没有未归类的笔记",
                           message: "新建的笔记会先进这里，之后可以在笔记页顶部改归属。")
        case .folder:
            VStack(spacing: AppSpacing.md) {
                EmptyStateView(icon: "folder",
                               title: "这个文件夹还是空的",
                               message: "把已有笔记移进来，或者直接在这里新建一条。")
                Button("查看全部笔记") { filter = .all }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .padding(.horizontal, AppSpacing.xl)
            }
        }
    }

    private var composeButton: some View {
        Button(action: createNote) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .padding(.trailing, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
        .accessibilityLabel("新建笔记")
        .accessibilityIdentifier("notes.compose")
    }

    // MARK: 动作

    private func select(_ chip: FolderChip) {
        guard let next = FolderChipBar.toggled(current: filter, tapped: chip) else { return }
        filter = next
    }

    /// 新建笔记落在**当前筛选**的文件夹里；「全部」/「未归类」下落进未归类。
    /// 在一个文件夹里点新建却生成一条未归类笔记会很意外。
    private func createNote() {
        let target: Folder?
        if case .folder(let id) = filter {
            target = folders.first { $0.id.uuidString == id }
        } else {
            target = nil
        }
        let card = Card(folder: target)
        modelContext.insert(card)
        commit()
        router.push(.note(card: card, anchor: nil))
    }

    private func togglePin(_ card: Card) {
        // 置顶不改 updatedAt —— 置顶的笔记要保持原有的时间顺序。
        card.isPinned.toggle()
        try? modelContext.save()
    }

    private func export(_ card: Card, _ format: CardExportFormat) {
        do {
            shareItems = [try CardExportService.writeTempFile(for: card, format: format)]
            showShare = true
        } catch {
            // 导出失败不该静默 —— 但也不值得一个 alert 打断浏览。
            shareItems = []
        }
    }

    private func delete(_ card: Card) {
        let noteID = card.id.uuidString
        for block in card.blocks ?? [] { MediaStore.shared.deleteMedia(for: block) }
        modelContext.delete(card)
        try? modelContext.save()
        // derived 数据在另一个 container 里，没有 cascade 能到达它。
        if let retrieval {
            Task { await retrieval.noteWasDeleted(noteID) }
        }
    }

    private func commit() {
        try? modelContext.save()
    }
}

// MARK: - 文件夹 chip 行

struct FolderChipRow: View {
    let chips: [FolderChip]
    let selected: NoteFilter
    let onSelect: (FolderChip) -> Void
    let onManage: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(chips) { chip in
                    Button {
                        if chip.role == .manage { onManage() } else { onSelect(chip) }
                    } label: {
                        chipLabel(chip)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("notes.chip.\(chip.id)")
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
        }
    }

    private func isSelected(_ chip: FolderChip) -> Bool { chip.filter == selected }

    @ViewBuilder private func chipLabel(_ chip: FolderChip) -> some View {
        let active = isSelected(chip)
        HStack(spacing: 5) {
            if let icon = chip.iconName {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(active ? Color.white : Color(hex: chip.colorHex ?? "#0A84FF"))
            }
            Text(chip.title)
                .font(.subheadline)
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(height: 32)
        .background(
            Capsule().fill(active ? Color.accentColor : Color(.secondarySystemFill))
        )
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - 笔记行（§2.3）

/// 三组信息，一个点击区。
///
/// **去掉了**类型图标行、标签 chip、chevron —— 它们进笔记页一眼可见，
/// 在列表里是噪音；去掉后一屏能多容纳约 40% 的笔记。
struct NoteRowView: View {
    let card: Card

    private var secondary: String? {
        let oneLiner = (card.summary?.hasBase == true) ? card.summary?.baseOneLiner : nil
        return NoteListPresentation.secondaryLine(oneLiner: oneLiner, blocks: card.blockContents())
    }

    private var hasUnread: Bool {
        (card.summary?.updateLogs ?? []).contains { !$0.isRead }
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: AppSpacing.xs) {
                    if card.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("已置顶")
                    }
                    Text(card.displayTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: AppSpacing.sm)
                    Text(Format.relative(card.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let secondary {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            if hasUnread {
                Circle().fill(.red).frame(width: 8, height: 8)
                    .padding(.top, 6)
                    .accessibilityLabel("有未读的更新总结")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 移动到文件夹（§2.4，本次新补的功能）

/// 引入「未归类」之后它从锦上添花变成必需品 —— 否则草草记下的笔记永远出不了未归类。
struct MoveToFolderSheet: View {
    @Bindable var card: Card
    let folders: [Folder]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    move(to: nil)
                } label: {
                    HStack {
                        Label("未归类", systemImage: "tray")
                        Spacer()
                        if card.folder == nil { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                .buttonStyle(.plain)

                ForEach(folders) { folder in
                    Button {
                        move(to: folder)
                    } label: {
                        HStack {
                            Label {
                                Text(folder.name)
                            } icon: {
                                Image(systemName: folder.iconName)
                                    .foregroundStyle(Color(hex: folder.colorHex))
                            }
                            Spacer()
                            if card.folder?.id == folder.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("移动到文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func move(to folder: Folder?) {
        card.folder = folder
        card.touch()
        onDone()
        dismiss()
    }
}
