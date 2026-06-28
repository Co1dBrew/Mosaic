import SwiftUI
import SwiftData
import MosaicKit

/// Folder detail: the collapsed card list (PRD §4.4).
struct CardListView: View {
    let folder: Folder

    @Environment(\.modelContext) private var modelContext
    @State private var selectedCard: Card?
    @State private var expandedCardIDs: Set<UUID> = []
    @State private var cardToDelete: Card?

    private var cards: [Card] { folder.sortedCards }

    var body: some View {
        Group {
            if cards.isEmpty {
                EmptyStateView(
                    icon: "note.text.badge.plus",
                    title: "还没有卡片",
                    message: "点击右上角 ＋ 写下第一条笔记,文字、录音、图片、文档、链接都能塞进来。"
                )
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
        for block in card.blocks ?? [] { MediaStore.shared.deleteMedia(for: block) }
        modelContext.delete(card)
        folder.touch()
        try? modelContext.save()
    }
}
