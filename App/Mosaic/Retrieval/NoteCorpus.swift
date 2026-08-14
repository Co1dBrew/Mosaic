import Foundation
import SwiftData
import MosaicKit

/// # 语料读取（Developer Tools 共用）
///
/// Lab 与 Eval 必须看到**同一份语料**，否则「Lab 里排第 2、Eval 里说没命中」这种
/// 差异会被归因到检索策略上，而实际只是两处各自切了一遍 chunk。所以切分只有这一处实现。
///
/// **只读**：不写笔记、不写索引（`DEVTOOLS.md` §1.2「数据隔离」）。
@MainActor
struct NoteCorpus {

    struct NoteSummary: Identifiable, Hashable {
        let id: String
        let title: String
        /// 正文开头。**标注 Golden 用例时必须有它**：`displayTitle` 在没有用户标题、
        /// 也没有 AI 标题时一律是「未命名笔记」，一屏全是同名笔记就没法选期望笔记了。
        /// 这是在模拟器上实跑标注流程时发现的。
        let preview: String
        let updatedAt: Date
    }

    let noteContext: ModelContext
    let derived: DerivedDataStore

    /// 用指定策略把全部笔记切成 chunk。
    ///
    /// 每次都现切而不缓存：Lab / Eval 的价值就在于换一个策略立刻看到差别，
    /// 缓存会让「换了策略但结果没变」变成一个假象。
    func chunks(strategy: ChunkStrategy) -> [NoteChunk] {
        cards().flatMap { card -> [NoteChunk] in
            let noteID = card.id.uuidString
            return ChunkPipeline.chunks(noteID: noteID,
                                        blocks: card.blockContents(),
                                        strategy: strategy,
                                        ocrTextByBlockID: derived.ocrTextByBlockID(noteID: noteID))
        }
    }

    func title(noteID: String) -> String {
        guard let uuid = UUID(uuidString: noteID) else { return "未知笔记" }
        var fetch = FetchDescriptor<Card>(predicate: #Predicate { $0.id == uuid })
        fetch.fetchLimit = 1
        return (try? noteContext.fetch(fetch))?.first?.displayTitle ?? "未知笔记（已删除）"
    }

    /// 供 Golden Set 标注时挑选期望笔记。
    func notes() -> [NoteSummary] {
        cards()
            .map { card in
                NoteSummary(id: card.id.uuidString,
                            title: card.displayTitle,
                            preview: preview(of: card),
                            updatedAt: card.updatedAt)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 正文开头 60 字。取的是 chunk 管线认得的那份文本（含 OCR），
    /// 所以「界面上看到的」与「被检索的」是同一份东西。
    private func preview(of card: Card) -> String {
        let noteID = card.id.uuidString
        let ocr = derived.ocrTextByBlockID(noteID: noteID)
        for block in card.blockContents() {
            guard let (_, text) = ChunkPipeline.resolveText(block: block, ocrText: ocr[block.id]) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            return trimmed.count > 60 ? String(trimmed.prefix(60)) + "…" : trimmed
        }
        return "（无可检索文本）"
    }

    /// 用来判断评测用例引用的笔记是否还在。
    func existingNoteIDs() -> Set<String> {
        Set(cards().map { $0.id.uuidString })
    }

    private func cards() -> [Card] {
        (try? noteContext.fetch(FetchDescriptor<Card>())) ?? []
    }
}
