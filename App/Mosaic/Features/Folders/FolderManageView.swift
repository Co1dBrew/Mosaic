import SwiftUI
import SwiftData
import MosaicKit

/// # 文件夹管理页（`UI_REDESIGN.md` v2 §5）
///
/// 原来的 `FolderListView`（首页）降级为二级页，由首页 chip 行末尾的 `⋯` 进入。
/// 职责收窄为**只管增删改排序**，不再承担导航。
///
/// 相比旧版新增：**拖动排序**。`sortOrder` 字段一直存在，PRD §4.1 把它标为 P1，
/// 差的只是 UI。
///
/// 「未归类」不出现在这里 —— 它不是真文件夹（`folder == nil`），
/// 不可重命名、不可删除。
struct FolderManageView: View {
    @Environment(\.modelContext) private var modelContext
    /// 可选：Preview / 测试里没有注入检索栈。删除路径必须在它缺席时仍然正确。
    @Environment(RetrievalEnvironment.self) private var retrieval: RetrievalEnvironment?
    @Query(sort: [SortDescriptor(\Folder.sortOrder), SortDescriptor(\Folder.createdAt)])
    private var folders: [Folder]

    @State private var editingFolder: Folder?
    @State private var isCreating = false
    @State private var folderToDelete: Folder?

    var body: some View {
        Group {
            if folders.isEmpty {
                EmptyStateView(
                    icon: "folder.badge.plus",
                    title: "还没有文件夹",
                    message: "点右上角 ＋ 新建一个。没有文件夹时，笔记都在「全部」里，一样能搜到。"
                )
            } else {
                List {
                    ForEach(folders) { folder in
                        FolderRowView(folder: folder)
                            .contentShape(Rectangle())
                            .onTapGesture { editingFolder = folder }
                            // 稳定 id：UI 测试要能点到**某一个具体的**文件夹，
                            // 而名字是用户输入的、会变。
                            .accessibilityIdentifier("folders.row.\(folder.id.uuidString)")
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { folderToDelete = folder } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                .accessibilityIdentifier("folders.delete.\(folder.id.uuidString)")
                                Button { editingFolder = folder } label: {
                                    Label("重命名", systemImage: "pencil")
                                }.tint(.orange)
                            }
                    }
                    .onMove(perform: move)
                }
                .listStyle(.insetGrouped)
                .accessibilityIdentifier("folders.list")
            }
        }
        .navigationTitle("文件夹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isCreating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("新建文件夹")
                    .accessibilityIdentifier("folders.create")
            }
            // 拖动排序在 `List` 里本来就长按即可拖，`EditButton` 只是给一条更明显的路径。
            if !folders.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .sheet(isPresented: $isCreating) {
            FolderEditSheet(folder: nil, nextSortOrder: (folders.map(\.sortOrder).max() ?? -1) + 1) { result in
                let folder = Folder(name: result.name, colorHex: result.colorHex,
                                    iconName: result.iconName, sortOrder: result.sortOrder)
                modelContext.insert(folder)
                try? modelContext.save()
            }
        }
        .sheet(item: $editingFolder) { folder in
            FolderEditSheet(folder: folder, nextSortOrder: folder.sortOrder) { result in
                folder.name = result.name
                folder.colorHex = result.colorHex
                folder.iconName = result.iconName
                folder.touch()
                try? modelContext.save()
            }
        }
        .alert("删除文件夹", isPresented: Binding(get: { folderToDelete != nil },
                                            set: { if !$0 { folderToDelete = nil } })) {
            Button("取消", role: .cancel) { folderToDelete = nil }
            Button("删除", role: .destructive) {
                if let folder = folderToDelete { delete(folder) }
                folderToDelete = nil
            }
            .accessibilityIdentifier("folders.confirmDelete")
        } message: {
            if let folder = folderToDelete {
                Text("将同时删除其中 \(folder.cardCount) 张笔记，此操作不可撤销。")
            }
        }
    }

    /// 拖动之后重排 `sortOrder`。**连续重编号**，不用「插在两者之间」的浮点技巧 ——
    /// 文件夹是几十条量级，重编号一次的代价可以忽略，而连续整数不会在多次拖动后
    /// 挤到精度极限。
    private func move(from source: IndexSet, to destination: Int) {
        var ordered = folders
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, folder) in ordered.enumerated() where folder.sortOrder != index {
            folder.sortOrder = index
        }
        try? modelContext.save()
    }

    private func delete(_ folder: Folder) {
        // **先收集 noteID，再删。** cascade 之后 `folder.cards` 就拿不到了。
        let noteIDs = (folder.cards ?? []).map { $0.id.uuidString }
        for card in folder.cards ?? [] {
            for block in card.blocks ?? [] { MediaStore.shared.deleteMedia(for: block) }
        }
        modelContext.delete(folder)
        try? modelContext.save()
        // derived 数据在另一个 container 里，没有任何 cascade 能到达它。
        if let retrieval {
            Task { await retrieval.notesWereDeleted(noteIDs) }
        }
    }
}

/// 文件夹管理页的一行：图标 + 名称 + 笔记数。
///
/// 首页的 chip 行**不显示数量**（v2 §2.2：数量对「我要看哪个文件夹」没有帮助，
/// 只占宽度）；管理页显示，因为在这里数量正是判断「这个文件夹还要不要」的依据。
struct FolderRowView: View {
    let folder: Folder

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(hex: folder.colorHex))
                    .frame(width: 38, height: 38)
                Image(systemName: folder.iconName)
                    .foregroundStyle(.white)
                    .font(.system(size: 17, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name).font(.body)
                Text("\(folder.cardCount) 张卡片")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
