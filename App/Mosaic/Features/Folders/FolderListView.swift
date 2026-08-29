import SwiftUI
import SwiftData

/// Home screen: the folder list (PRD §4.1).
struct FolderListView: View {
    @Environment(\.modelContext) private var modelContext
    /// 可选：Preview / 测试里没有注入检索栈。删除路径必须在它缺席时仍然正确 ——
    /// 只是那时没有 derived 数据要清。
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
                    message: "点击右上角 ＋ 新建一个文件夹,开始记录你的第一条笔记。"
                )
            } else {
                List {
                    ForEach(folders) { folder in
                        NavigationLink(value: folder) {
                            FolderRowView(folder: folder)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { folderToDelete = folder } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button { editingFolder = folder } label: {
                                Label("重命名", systemImage: "pencil")
                            }.tint(.orange)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("万象记")
        .navigationDestination(for: Folder.self) { folder in
            CardListView(folder: folder)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    SearchView()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                Button { isCreating = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            FolderEditSheet(folder: nil, nextSortOrder: (folders.map(\.sortOrder).max() ?? -1) + 1) { result in
                let folder = Folder(name: result.name, colorHex: result.colorHex, iconName: result.iconName, sortOrder: result.sortOrder)
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
        .alert("删除文件夹", isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } })) {
            Button("取消", role: .cancel) { folderToDelete = nil }
            Button("删除", role: .destructive) {
                if let folder = folderToDelete { delete(folder) }
                folderToDelete = nil
            }
        } message: {
            if let folder = folderToDelete {
                Text("将同时删除其中 \(folder.cardCount) 张卡片,此操作不可撤销。")
            }
        }
    }

    private func delete(_ folder: Folder) {
        // **先收集 noteID，再删。** cascade 删完之后 `folder.cards` 已经拿不到了，
        // 那时再想知道「刚刚删掉的是哪几篇」就只能靠对账去猜。
        let noteIDs = (folder.cards ?? []).map { $0.id.uuidString }
        // Clean up media files for all blocks before cascade delete.
        for card in folder.cards ?? [] {
            for block in card.blocks ?? [] { MediaStore.shared.deleteMedia(for: block) }
        }
        modelContext.delete(folder)
        try? modelContext.save()
        // derived 数据在另一个 container 里，**没有任何 cascade 能到达它**。
        // 漏掉这一步 = 残留向量继续进 topK，搜索页回查笔记失败后静默丢行。
        if let retrieval {
            Task { await retrieval.notesWereDeleted(noteIDs) }
        }
    }
}

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
