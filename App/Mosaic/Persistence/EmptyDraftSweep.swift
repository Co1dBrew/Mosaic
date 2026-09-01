import Foundation
import SwiftData
import MosaicKit

/// # 启动时清掉「幽灵空笔记」
///
/// ## 它补的是哪个洞
///
/// 空白草稿的正常丢弃发生在**退出笔记页**时（`NoteDetailView.handleExit`）。
/// 但那条路径依赖 `onDisappear` 真的跑到 —— 而它在一种情况下跑不到：
/// **用户在新建的空笔记里，直接把 App 划掉 / 系统回收了进程。**
///
/// 那时数据库里留下一条什么都没有的笔记，下次启动就出现在笔记流里。
/// 一次两次是噪声，反复发生就是「未命名笔记 / 未命名笔记 / 未命名笔记」。
///
/// ## 为什么可以放心删
///
/// 判据是**内核那一条**（`NoteDraftPolicy.hasMeaningfulContent`），不是另写一份：
/// 标题、标签、任意非空内容块（文字 / 图片 / 录音 / 文档 / 链接）
/// 有任何一样就不动。空白字符 trim 后判空。
///
/// 也就是说，被删掉的只可能是**一条用户看不到任何内容的笔记**。
/// 它没有可失去的东西 —— 这正是「新建后什么都没写」留下的那个东西。
///
/// ## 三条克制
///
/// 1. **不看时间、不看「是不是这次启动前建的」。** 加时间窗口会让规则变成
///    「有时候清有时候不清」，而用户无法预测的清理比不清理更糟。
/// 2. **摘要不算内容。** 摘要是 App 生成的，不是用户写的；
///    一条只有摘要没有正文的笔记本来就不该存在。
/// 3. **derived 数据跟着一起清。** 不清的话就是在修一个洞的同时挖另一个 ——
///    上一轮 D1（删文件夹的 derived 泄漏）修的正是这件事。
enum EmptyDraftSweep {

    /// - Parameters:
    ///   - context: 笔记所在的上下文。
    ///   - derivedTexts: 给一条笔记取 OCR / 转写文本。与 `NoteDetailView` 同一个口径。
    /// - Returns: 被清掉的 noteID。调用方负责用它清 derived 数据。
    @MainActor
    @discardableResult
    static func sweep(context: ModelContext,
                      derivedTexts: (Card) -> [String] = { _ in [] }) -> [String] {
        guard let cards = try? context.fetch(FetchDescriptor<Card>()) else { return [] }

        let ghosts = cards.filter { card in
            !NoteDraftPolicy.hasMeaningfulContent(title: card.userTitle,
                                                  tags: card.tags,
                                                  blocks: card.blockContents(),
                                                  derivedTexts: derivedTexts(card))
        }
        guard !ghosts.isEmpty else { return [] }

        let ids = ghosts.map { $0.id.uuidString }
        for card in ghosts {
            for block in card.blocks ?? [] { MediaStore.shared.deleteMedia(for: block) }
            context.delete(card)
        }
        try? context.save()
        return ids
    }
}
