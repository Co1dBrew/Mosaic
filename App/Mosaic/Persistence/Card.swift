import Foundation
import SwiftData
import MosaicKit

/// A note card — the core unit, holding an ordered list of mixed content blocks
/// (PRD §4.2 / §8).
@Model
final class Card {
    var id: UUID = UUID()
    /// Optional user title; when empty the AI summary may supply one (PRD §4.2 / §4.8).
    var userTitle: String = ""
    var isPinned: Bool = false
    /// User tags (PRD §4.9). Stored as a defaulted [String] — same shape as the
    /// already-synced topic/keypoint arrays, so it's a safe SwiftData lightweight
    /// migration (old cards default to []) and CloudKit-compatible.
    var tags: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Block.card)
    var blocks: [Block]? = []

    @Relationship(deleteRule: .cascade, inverse: \AISummaryEntity.card)
    var summary: AISummaryEntity?

    init(userTitle: String = "", folder: Folder? = nil) {
        self.id = UUID()
        self.userTitle = userTitle
        self.folder = folder
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Blocks in document order (PRD §4.3 block-based linear document).
    var orderedBlocks: [Block] {
        (blocks ?? []).sorted { $0.order < $1.order }
    }

    /// The next order index to assign when appending a block.
    var nextBlockOrder: Int {
        (blocks ?? []).map(\.order).max().map { $0 + 1 } ?? 0
    }

    /// Title shown in the collapsed bar: user title, else AI title, else fallback.
    var displayTitle: String {
        let t = userTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let aiTitle = summary?.baseTitle.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !aiTitle.isEmpty { return aiTitle }
        return "未命名笔记"
    }

    /// The distinct content types present, for the collapsed-bar icon row (PRD §4.4).
    var presentKinds: [BlockKind] {
        var seen = Set<BlockKind>()
        var ordered: [BlockKind] = []
        for b in orderedBlocks where !seen.contains(b.kind) {
            seen.insert(b.kind); ordered.append(b.kind)
        }
        return ordered
    }

    var isEmpty: Bool { orderedBlocks.allSatisfy { $0.isEffectivelyEmpty } }

    func touch() {
        updatedAt = Date()
        folder?.touch()
    }

    // MARK: Tags (normalized + de-duped via MosaicKit TagUtilities)

    func addTag(_ raw: String) {
        let updated = TagUtilities.add(raw, to: tags)
        if updated != tags { tags = updated; touch() }
    }

    func removeTag(_ tag: String) {
        let updated = TagUtilities.remove(tag, from: tags)
        if updated != tags { tags = updated; touch() }
    }

    func addTopicsAsTags(_ topics: [String]) {
        let updated = TagUtilities.addingTopics(topics, to: tags)
        if updated != tags { tags = updated; touch() }
    }

    /// Builds the platform-agnostic content snapshot consumed by MosaicKit.
    func blockContents() -> [CardBlockContent] {
        orderedBlocks.map { $0.toContent() }
    }
}
