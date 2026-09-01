import Foundation

/// # 一条新建的笔记，什么时候才算「真的存在」
///
/// ## 产品规则
///
/// 点「新建」只表达**一次创建意图**，不等于数据库里已经有了一条永久笔记。
/// 用户什么都没写就离开 → **不该留下任何东西**。
///
/// 在这条规则之前，每一次误触悬浮按钮都会在笔记流里留下一行「未命名笔记」，
/// 而清理它要用户自己去长按删除 —— 一个由 App 制造、却要用户收拾的烂摊子。
///
/// ## 为什么判定在内核里
///
/// 「有没有有效内容」是一个纯粹的取值规则，与 SwiftData / SwiftUI 无关。
/// 放在内核意味着它可以被逐条单测，而不必起一个 App target。
/// 更要紧的是：**它必须只有一处实现**。两处实现迟早会在
/// 「图片算不算内容」这种问题上分叉，而分叉的后果是用户的笔记被删掉。
public enum NoteDraftPolicy {

    /// 这条笔记有没有**任何**有效内容。
    ///
    /// - Parameters:
    ///   - title: 用户手输的标题。**不要传 `displayTitle`** —— 空标题的回退文案
    ///     是「未命名笔记」，那会让每一条空笔记都被判成「有内容」，
    ///     这条规则就整个失效了。
    ///   - tags: 标签。用户特地打了标签，即使正文空着也是一次真实的动作。
    ///   - blocks: 内容块。文字 / 图片 / 录音 / 文档 / 链接。
    ///   - derivedTexts: 衍生文本（OCR / 转写）。它们**不是**用户直接输入的，
    ///     但它们的存在证明这条笔记里有过真实媒体 —— 而媒体块本身也会被
    ///     `blocks` 判到，所以这一项是兜底，不是主判据。
    ///
    /// **空白字符不算内容**：`""` / `" "` / `"\n\n"` / `"\t"` 全部 trim 后判空。
    public static func hasMeaningfulContent(title: String?,
                                            tags: [String] = [],
                                            blocks: [CardBlockContent],
                                            derivedTexts: [String] = []) -> Bool {
        if !isBlank(title) { return true }
        if tags.contains(where: { !isBlank($0) }) { return true }
        // 块的判定复用 `NoteListPresentation` 那一套 —— 「这个块算不算空」
        // 在列表副标题、摘要触发、这里，三处必须是同一个答案。
        if !NoteListPresentation.isEmptyNote(blocks) { return true }
        if derivedTexts.contains(where: { !isBlank($0) }) { return true }
        return false
    }

    /// 一条**新建的草稿**在退出时该不该被丢弃。
    ///
    /// `isNewDraft` 是必需的第二个条件，不是可选的谨慎：
    /// **已有笔记被用户清空，不能自动删除。** 那是用户的数据，
    /// 「清空」和「删除」是两个不同的意图，替他做决定是越权
    /// —— 何况删除入口本来就在 `⋯` 菜单里，一步可达。
    public static func shouldDiscardOnExit(isNewDraft: Bool,
                                           title: String?,
                                           tags: [String] = [],
                                           blocks: [CardBlockContent],
                                           derivedTexts: [String] = []) -> Bool {
        guard isNewDraft else { return false }
        return !hasMeaningfulContent(title: title, tags: tags,
                                     blocks: blocks, derivedTexts: derivedTexts)
    }

    private static func isBlank(_ s: String?) -> Bool {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
