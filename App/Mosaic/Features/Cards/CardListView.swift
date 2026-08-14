import SwiftUI
import SwiftData
import MosaicKit

/// Folder detail: the collapsed card list (PRD §4.4).
struct CardListView: View {
    let folder: Folder

    @Environment(\.modelContext) private var modelContext
    @Environment(RetrievalEnvironment.self) private var retrieval: RetrievalEnvironment?
    @State private var selectedCard: Card?
    @State private var expandedCardIDs: Set<UUID> = []
    @State private var cardToDelete: Card?
    @State private var selectedTag: String?

    /// All tags used by cards in this folder (normalized + de-duped).
    private var folderTags: [String] {
        TagUtilities.sanitize((folder.cards ?? []).flatMap { $0.tags })
    }

    private var cards: [Card] {
        let base = folder.sortedCards
        guard let tag = selectedTag else { return base }
        return base.filter { TagUtilities.contains(tag, in: $0.tags) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !folderTags.isEmpty {
                tagFilterBar
            }
            content
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedCard) { card in
            CardEditorView(card: card)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { createCard() } label: { Image(systemName: "square.and.pencil") }
            }
        }
        .alert("删除卡片", isPresented: Binding(get: { cardToDelete != nil }, set: { if !$0 { cardToDelete = nil } })) {
            Button("取消", role: .cancel) { cardToDelete = nil }
            Button("删除", role: .destructive) {
                if let card = cardToDelete { delete(card) }
                cardToDelete = nil
            }
        } message: {
            Text("此操作不可撤销。")
        }
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(folderTags, id: \.self) { tag in
                    Button {
                        selectedTag = (selectedTag == tag) ? nil : tag
                    } label: {
                        TagChip(text: tag, isSelected: selectedTag == tag)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
        }
    }

    @ViewBuilder private var content: some View {
        if cards.isEmpty {
            if selectedTag != nil {
                EmptyStateView(
                    icon: "tag.slash",
                    title: "该标签下没有卡片",
                    message: "点击上方标签可取消筛选。"
                )
            } else {
                EmptyStateView(
                    icon: "note.text.badge.plus",
                    title: "还没有卡片",
                    message: "点击右上角 ＋ 写下第一条笔记,文字、录音、图片、文档、链接都能塞进来。"
                )
            }
        } else {
            List {
                ForEach(cards) { card in
                    CardRowView(
                        card: card,
                        isExpanded: expandedCardIDs.contains(card.id),
                        onOpen: { selectedCard = card },
                        onToggleExpand: { toggleExpand(card) }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
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
                }
            }
            .listStyle(.plain)
        }
    }

    /// Toggles pin without bumping updatedAt, so pinned cards keep their
    /// relative recency order (PRD: pinned still sorted by updatedAt desc).
    private func togglePin(_ card: Card) {
        card.isPinned.toggle()
        try? modelContext.save()
    }

    private func toggleExpand(_ card: Card) {
        if expandedCardIDs.contains(card.id) {
            expandedCardIDs.remove(card.id)
        } else {
            expandedCardIDs.insert(card.id)
        }
    }

    private func createCard() {
        let card = Card(folder: folder)
        modelContext.insert(card)
        folder.touch()
        try? modelContext.save()
        selectedCard = card
    }

    private func delete(_ card: Card) {
        let noteID = card.id.uuidString
        for block in card.blocks ?? [] { MediaStore.shared.deleteMedia(for: block) }
        modelContext.delete(card)
        folder.touch()
        try? modelContext.save()
        // derived 数据必须跟着笔记走 —— 留下来的向量会让搜索命中一篇已经不存在的笔记。
        if let retrieval {
            Task { await retrieval.noteWasDeleted(noteID) }
        }
    }
}
