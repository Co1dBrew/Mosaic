import Foundation
import MosaicKit

/// # 空白新建草稿的判定（`NoteDraftPolicy`）
///
/// 这一组守的是一条**会删除用户数据**的规则，所以它的断言分两半：
///
/// - 一半证明「该丢的会丢」（空草稿不留下未命名笔记）
/// - 另一半证明「**不该丢的绝不丢**」—— 有标题的、有标签的、只有图片的、
///   只有录音的、以及**任何已有笔记**
///
/// 第二半更重要。第一半错了是留下一行垃圾，第二半错了是删掉用户的笔记。
enum NoteDraftChecks {

    static func run(_ r: CheckRunner) {
        checkEmptyDraftIsDiscarded(r)
        checkMeaningfulContentIsKept(r)
        checkExistingNotesAreNeverAutoDeleted(r)
    }

    // MARK: 工具

    private static func text(_ s: String) -> CardBlockContent {
        CardBlockContent(id: "b-text", order: 0, kind: .text, text: s)
    }
    private static func image(_ ref: String) -> CardBlockContent {
        CardBlockContent(id: "b-img", order: 0, kind: .image, imageAssetRef: ref)
    }
    private static func audio(_ ref: String) -> CardBlockContent {
        CardBlockContent(id: "b-aud", order: 0, kind: .audio, audioAssetRef: ref)
    }
    private static func file(_ name: String) -> CardBlockContent {
        CardBlockContent(id: "b-doc", order: 0, kind: .file, fileName: name)
    }
    private static func link(_ url: String) -> CardBlockContent {
        CardBlockContent(id: "b-link", order: 0, kind: .link, url: url)
    }

    // MARK: 1 · 该丢的会丢

    private static func checkEmptyDraftIsDiscarded(_ r: CheckRunner) {
        r.suite("新建草稿 · 什么都没写就离开 → 不留下任何东西")

        r.expect(!NoteDraftPolicy.hasMeaningfulContent(title: nil, blocks: []),
                 "完全空的笔记没有有效内容")
        r.expect(!NoteDraftPolicy.hasMeaningfulContent(title: "", blocks: [text("")]),
                 "空标题 + 一个空文字块（这正是「点新建什么都没写」的形状）")

        // **空白字符不算内容。** 这一组是规则的实际边界 ——
        // 用户不小心碰到键盘打了个空格，不该因此得到一条永久笔记。
        for blank in [" ", "   ", "\n", "\n\n", "\t", " \n \t ", "\u{00A0}"] {
            r.expect(!NoteDraftPolicy.hasMeaningfulContent(title: blank, blocks: [text(blank)]),
                     "纯空白不算内容（\(blank.debugDescription)）")
        }

        r.expect(NoteDraftPolicy.shouldDiscardOnExit(isNewDraft: true, title: "  ",
                                                     blocks: [text("\n")]),
                 "新建草稿 + 全空白 → 丢弃")
    }

    // MARK: 2 · 不该丢的绝不丢

    private static func checkMeaningfulContentIsKept(_ r: CheckRunner) {
        r.suite("新建草稿 · 有任何一样内容就必须留下")

        r.expect(NoteDraftPolicy.hasMeaningfulContent(title: "会议纪要", blocks: [text("")]),
                 "只有标题也算 —— 用户特地起了名字")
        r.expect(NoteDraftPolicy.hasMeaningfulContent(title: nil, blocks: [text("排期定了")]),
                 "只有正文也算")
        r.expect(NoteDraftPolicy.hasMeaningfulContent(title: "", tags: ["学业"], blocks: [text("")]),
                 "只有标签也算 —— 打标签是一次真实的动作")
        r.expect(!NoteDraftPolicy.hasMeaningfulContent(title: "", tags: ["  "], blocks: [text("")]),
                 "但纯空白的标签不算")

        // **媒体笔记**：标题正文都空，只有一个附件。这一类最容易被
        // 「`text.isEmpty` 就删」的实现误杀 —— 而误杀的是用户刚拍的照片、刚录的音。
        r.expect(NoteDraftPolicy.hasMeaningfulContent(title: nil, blocks: [image("photo.jpg")]),
                 "只有图片也算")
        r.expect(NoteDraftPolicy.hasMeaningfulContent(title: nil, blocks: [audio("rec.m4a")]),
                 "只有录音也算")
        r.expect(NoteDraftPolicy.hasMeaningfulContent(title: nil, blocks: [file("合同.pdf")]),
                 "只有文档也算")
        r.expect(NoteDraftPolicy.hasMeaningfulContent(title: nil, blocks: [link("https://x.test")]),
                 "只有链接也算")

        // 衍生文本兜底：媒体引用丢了，但识别出来的文字还在 ——
        // 那时这条笔记里仍然有用户能搜到的东西。
        r.expect(NoteDraftPolicy.hasMeaningfulContent(title: nil, blocks: [text("")],
                                                      derivedTexts: ["发票金额 128 元"]),
                 "只有 OCR / 转写文本也算")
        r.expect(!NoteDraftPolicy.hasMeaningfulContent(title: nil, blocks: [text("")],
                                                       derivedTexts: ["  ", ""]),
                 "但空白的衍生文本不算")

        for (label, blocks) in [("图片", [image("p.jpg")]), ("录音", [audio("a.m4a")]),
                                ("文档", [file("d.pdf")]), ("链接", [link("https://x.test")])] {
            r.expect(!NoteDraftPolicy.shouldDiscardOnExit(isNewDraft: true, title: nil, blocks: blocks),
                     "只有\(label)的新建笔记**不丢弃**")
        }
    }

    // MARK: 3 · 已有笔记永远不自动删

    private static func checkExistingNotesAreNeverAutoDeleted(_ r: CheckRunner) {
        r.suite("新建草稿 · 这条规则只管新建，不管已有笔记")

        // 用户打开一条老笔记、把内容全删空、退出 —— **不能替他删掉这条笔记**。
        // 「清空」和「删除」是两个不同的意图；删除入口在 `⋯` 菜单里，一步可达。
        r.expect(!NoteDraftPolicy.shouldDiscardOnExit(isNewDraft: false, title: "",
                                                      blocks: [text("")]),
                 "已有笔记被清空 → **不丢弃**")
        r.expect(!NoteDraftPolicy.shouldDiscardOnExit(isNewDraft: false, title: "   ",
                                                      blocks: [text("\n\n")]),
                 "已有笔记只剩空白 → 仍然**不丢弃**")

        // 同样的内容，只有 isNewDraft 不同，结论必须相反 ——
        // 否则这个参数就是个摆设。
        let sameArgs: (Bool) -> Bool = {
            NoteDraftPolicy.shouldDiscardOnExit(isNewDraft: $0, title: "", blocks: [text(" ")])
        }
        r.expect(sameArgs(true) && !sameArgs(false),
                 "同样的空内容，新建丢弃 / 已有保留 —— isNewDraft 真的在起作用")
    }
}
