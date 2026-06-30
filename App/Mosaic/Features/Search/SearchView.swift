import SwiftUI
import SwiftData
import MosaicKit

/// Global card search (PRD §4.9). Phase 1 is global-only, but the filtering goes
/// through `SearchScope`, so folder / tag / pinned filters can be added later
/// without touching this view's structure.
struct SearchView: View {
    @Query(sort: [SortDescriptor(\Card.updatedAt, order: .reverse)]) private var allCards: [Card]

    var initialQuery: String = ""

    @State private var query = ""
    @State private var debounced = ""
    @State private var results: [Card] = []
    @State private var selectedCard: Card?

    private var trimmedQuery: String {
        debounced.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "搜索全部笔记",
                    message: "输入关键词,搜索标题、文字、转写稿、链接、文档与 AI 摘要。"
                )
            } else if results.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "没有找到匹配的卡片",
                    message: "换个关键词试试。"
                )
            } else {
                List(results) { card in
                    Button { selectedCard = card } label: {
                        SearchResultRow(card: card)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索全部笔记")
        .task(id: query) {
            // Debounce: only recompute ~250ms after typing stops, off the keystroke path.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            debounced = query
            results = computeResults(for: query)
        }
        .navigationDestination(item: $selectedCard) { card in
            CardEditorView(card: card)
        }
        .onAppear {
            if query.isEmpty && !initialQuery.isEmpty { query = initialQuery }
        }
    }

    /// Runs on the main actor (SwiftData), gated by the debounce so it executes at
    /// most every ~250ms rather than per keystroke.
    private func computeResults(for rawQuery: String) -> [Card] {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let scope = SearchScope() // Phase 1: global
        return allCards.filter { card in
            scope.allows(folderID: card.folder?.id.uuidString, tags: CardSearchText.tags(for: card), isPinned: card.isPinned)
                && SearchMatcher.matches(query: q, haystack: CardSearchText.haystack(for: card), tags: CardSearchText.tags(for: card))
        }
    }
}

private struct SearchResultRow: View {
    let card: Card

    private var oneLiner: String? {
        guard let summary = card.summary, summary.hasBase else { return nil }
        let t = summary.baseOneLiner.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(card.displayTitle).font(.headline).lineLimit(1)
            if let oneLiner {
                Text(oneLiner).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: AppSpacing.sm) {
                if let folder = card.folder {
                    Label(folder.name, systemImage: folder.iconName)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(Format.relative(card.updatedAt)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .contentShape(Rectangle())
    }
}

/// Builds the searchable text for a card (PRD §4.9 scope). Kept in the app since
/// it reads SwiftData models; the matching itself lives in MosaicKit.
enum CardSearchText {
    static func haystack(for card: Card) -> String {
        var parts: [String] = [card.displayTitle]
        for block in card.orderedBlocks {
            switch block.kind {
            case .text:  parts.append(MarkdownText.plainText(from: block.text)) // search plain text, not Markdown markers
            case .audio: parts.append(block.transcript)
            case .file:  parts.append(block.fileName); parts.append(block.extractedText)
            case .link:  parts.append(block.url); parts.append(block.linkTitle); parts.append(block.linkDescription)
            case .image: parts.append(block.caption)
            }
        }
        if let summary = card.summary, summary.hasBase {
            parts.append(contentsOf: [summary.baseTitle, summary.baseOneLiner, summary.baseType, summary.baseSummary])
            parts.append(contentsOf: summary.baseTopics)
            parts.append(contentsOf: summary.baseKeyPoints)
            for log in summary.sortedUpdateLogs {
                parts.append(log.updateOneLiner)
                parts.append(contentsOf: log.changes)
            }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Tags participate in search (PRD §4.9).
    static func tags(for card: Card) -> [String] {
        card.tags
    }
}
