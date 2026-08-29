import Foundation
import MosaicKit

/// UI v2 的**取值规则**断言（`UI_REDESIGN.md` v2）。
///
/// 这些规则本可以直接写在 View 里，但那样就只能靠模拟器截图走查来验证 ——
/// 而最容易出错的恰恰是**没有数据的那几档**（新建笔记还没有摘要、笔记完全为空、
/// 文件夹一个都没有）。它们在截图走查里很难被想起来，在断言里很难被漏掉。
enum NotesUIChecks {

    static func run(_ r: CheckRunner) {
        checkSecondaryLineFallback(r)
        checkContentTypeDescription(r)
        checkFolderChipBar(r)
        checkSummaryBarStates(r)
        checkSummaryOnExit(r)
        checkPermissionCopy(r)
    }

    // MARK: 工具

    private static func text(_ id: String, _ s: String, order: Int = 0) -> CardBlockContent {
        CardBlockContent(id: id, order: order, kind: .text, text: s)
    }
    private static func audio(_ id: String, order: Int = 0) -> CardBlockContent {
        CardBlockContent(id: id, order: order, kind: .audio,
                         transcript: "转写", audioDurationSec: 12, audioAssetRef: "a/\(id).m4a")
    }
    private static func image(_ id: String, order: Int = 0) -> CardBlockContent {
        CardBlockContent(id: id, order: order, kind: .image, imageAssetRef: "i/\(id).jpg")
    }

    // MARK: 1 · 笔记行第二行的三级回退（§2.3）

    private static func checkSecondaryLineFallback(_ r: CheckRunner) {
        r.suite("首页笔记行 · 第二行三级回退：AI 一句话 → 正文首行 → 内容类型")

        let blocks = [text("b1", "# 会议纪要\n今天讨论了**排期**与分工。")]

        r.expectEqual(NoteListPresentation.secondaryLine(oneLiner: "确定了排期与三位负责人", blocks: blocks),
                      "确定了排期与三位负责人",
                      "有 AI 一句话时优先用它")

        // 没有摘要 → 正文首行**纯文本**。Markdown 记号不能泄漏到列表里。
        let excerpt = NoteListPresentation.secondaryLine(oneLiner: nil, blocks: blocks)
        r.expectEqual(excerpt, "会议纪要", "回退到正文首行")
        r.expect(!(excerpt ?? "").contains("#") && !(excerpt ?? "").contains("*"),
                 "Markdown 记号不会泄漏到列表行 —— 这是 `MarkdownText.plainText` 的职责")

        // 空一句话（模型返回空串）等同于没有。
        r.expectEqual(NoteListPresentation.secondaryLine(oneLiner: "   ", blocks: blocks),
                      "会议纪要", "空白的一句话不算有摘要")

        // 只有录音 → 内容类型描述。这是新建一条语音笔记后的第一档。
        r.expectEqual(NoteListPresentation.secondaryLine(oneLiner: nil, blocks: [audio("a1")]),
                      "1 段录音", "没有文字时回退到内容类型")

        r.expectNil(NoteListPresentation.secondaryLine(oneLiner: nil, blocks: []),
                    "全空时返回 nil，由调用方决定留白 —— 不在这里编一句话")
        r.expectNil(NoteListPresentation.secondaryLine(oneLiner: nil, blocks: [text("b", "   \n  ")]),
                    "只有空白文字块 = 空笔记")
    }

    private static func checkContentTypeDescription(_ r: CheckRunner) {
        r.suite("首页笔记行 · 内容类型描述按固定顺序，不随块顺序变化")

        let a = NoteListPresentation.contentTypeDescription([image("i1", order: 0), audio("a1", order: 1)])
        let b = NoteListPresentation.contentTypeDescription([audio("a1", order: 0), image("i1", order: 1)])
        r.expectEqual(a, b, "同一批内容换个排序，描述必须相同 —— 否则会让人以为笔记变了")
        r.expectEqual(a, "1 张图片 · 1 段录音", "按 BlockKind 的固定顺序输出")

        r.expectNil(NoteListPresentation.contentTypeDescription([]), "没有内容就没有描述")
        r.expect(NoteListPresentation.isEmptyNote([text("b", "")]), "空文字块算空笔记")
        r.expect(!NoteListPresentation.isEmptyNote([image("i")]), "只有一张图也不算空")
    }

    // MARK: 2 · 文件夹 chip 行（§2.2）

    private static func checkFolderChipBar(_ r: CheckRunner) {
        r.suite("首页 chip 行 · 构成、隐藏条件、再次点击回到「全部」")

        let folders = [
            FolderChipSource(id: "f1", name: "工作", colorHex: "#0A84FF", iconName: "briefcase"),
            FolderChipSource(id: "f2", name: "读书", colorHex: "#FF9F0A", iconName: "book")
        ]

        r.expect(FolderChipBar.isHidden(folderCount: 0),
                 "一个用户文件夹都没有时整行隐藏 —— 新用户第一眼该看到笔记流，不是空的分类系统")
        r.expectEqual(FolderChipBar.chips(folders: [], hasUnfiledNotes: true), [],
                      "隐藏时不产出任何 chip（包括「全部」）")

        let withUnfiled = FolderChipBar.chips(folders: folders, hasUnfiledNotes: true)
        r.expectEqual(withUnfiled.map(\.id), ["all", "unfiled", "f1", "f2", "manage"],
                      "顺序：全部 → 未归类 → 用户文件夹（按 sortOrder）→ ⋯")

        let withoutUnfiled = FolderChipBar.chips(folders: folders, hasUnfiledNotes: false)
        r.expectEqual(withoutUnfiled.map(\.id), ["all", "f1", "f2", "manage"],
                      "没有未归类笔记时不显示「未归类」—— 一个永远空的筛选项只占宽度")

        let workChip = withUnfiled.first { $0.id == "f1" }!
        r.expectEqual(FolderChipBar.toggled(current: .all, tapped: workChip), .folder(id: "f1"),
                      "点一个文件夹 → 切到它")
        r.expectEqual(FolderChipBar.toggled(current: .folder(id: "f1"), tapped: workChip), .all,
                      "再次点击已选中的 chip → 回到「全部」")
        r.expectNil(FolderChipBar.toggled(current: .all, tapped: withUnfiled.last!),
                    "`⋯` 不改筛选，它是一次导航")

        r.expectEqual(FolderChipBar.title(for: .all, folders: folders), "全部笔记")
        r.expectEqual(FolderChipBar.title(for: .unfiled, folders: folders), "未归类")
        r.expectEqual(FolderChipBar.title(for: .folder(id: "f2"), folders: folders), "读书")
        r.expectEqual(FolderChipBar.title(for: .folder(id: "gone"), folders: folders), "全部笔记",
                      "文件夹刚被删掉时退回「全部笔记」，而不是显示空标题")
    }

    // MARK: 3 · 摘要条六种状态（§3.4）

    private static func checkSummaryBarStates(_ r: CheckRunner) {
        r.suite("笔记页摘要条 · 六种状态，尤其是「无摘要」的两档")

        // 新建笔记的第一秒：整条隐藏。
        r.expectEqual(NoteSummaryPresentation.barState(hasBase: false, oneLiner: "", noteIsEmpty: true,
                                                       isGenerating: false, errorMessage: nil,
                                                       errorIsConfiguration: false, hasUnreadUpdates: false),
                      .hidden, "无摘要 · 内容为空 → 整条隐藏")

        // 写了内容但还没退出：纯告知，**不可点**。
        let pending = NoteSummaryPresentation.barState(hasBase: false, oneLiner: "", noteIsEmpty: false,
                                                       isGenerating: false, errorMessage: nil,
                                                       errorIsConfiguration: false, hasUnreadUpdates: false)
        r.expectEqual(pending, .pending, "无摘要 · 有内容 → 告知「退出后将自动生成总结」")
        r.expect(!pending.isExpandable, "这一档不可展开 —— 没有东西可展开")
        r.expectEqual(NoteSummaryPresentation.collapsedText(pending), "退出后将自动生成总结")

        r.expectEqual(NoteSummaryPresentation.barState(hasBase: true, oneLiner: "一句话", noteIsEmpty: false,
                                                       isGenerating: true, errorMessage: nil,
                                                       errorIsConfiguration: false, hasUnreadUpdates: false),
                      .generating, "生成中优先于其它状态")

        let failed = NoteSummaryPresentation.barState(hasBase: true, oneLiner: "一句话", noteIsEmpty: false,
                                                      isGenerating: false, errorMessage: "Key 无效",
                                                      errorIsConfiguration: true, hasUnreadUpdates: false)
        r.expectEqual(failed, .failed(message: "Key 无效", opensSettings: true),
                      "配置类错误才给「去设置」")

        r.expectEqual(NoteSummaryPresentation.barState(hasBase: true, oneLiner: "确定了排期", noteIsEmpty: false,
                                                       isGenerating: false, errorMessage: nil,
                                                       errorIsConfiguration: false, hasUnreadUpdates: true),
                      .ready(oneLiner: "确定了排期", hasUnread: true))

        // 有 base 但一句话是空的：退回 pending 的文案，而不是显示一条空横条
        // （空横条看起来像加载卡住了）。
        r.expectEqual(NoteSummaryPresentation.barState(hasBase: true, oneLiner: "  ", noteIsEmpty: false,
                                                       isGenerating: false, errorMessage: nil,
                                                       errorIsConfiguration: false, hasUnreadUpdates: false),
                      .pending, "有 base 但一句话为空 → 不显示空横条")

        r.expectNil(NoteSummaryPresentation.collapsedText(.hidden), "隐藏态没有文字")
    }

    // MARK: 4 · 退出时的总结时机（§3.10）

    private static func checkSummaryOnExit(_ r: CheckRunner) {
        r.suite("退出笔记页 · 生成时机只有一条规则「写完退出就总结」")

        r.expectEqual(SummaryOnExit.action(autoUpdateEnabled: true, privacyAccepted: true,
                                           hasBase: false, hasContent: true, hasPendingChanges: false),
                      .generateBase,
                      "还没有初始总结 → 退出时生成它（v2 把它从 onAppear 挪到了这里）")

        r.expectEqual(SummaryOnExit.action(autoUpdateEnabled: true, privacyAccepted: true,
                                           hasBase: true, hasContent: true, hasPendingChanges: true),
                      .appendUpdate, "已有 base 且有实质变更 → 追加更新记录")

        r.expectEqual(SummaryOnExit.action(autoUpdateEnabled: true, privacyAccepted: true,
                                           hasBase: true, hasContent: true, hasPendingChanges: false),
                      .none, "没有实质变更就不花这次钱")

        // **只是点进去看一眼不会花钱** —— 这是 v2 相比旧行为更省的地方。
        r.expectEqual(SummaryOnExit.action(autoUpdateEnabled: true, privacyAccepted: true,
                                           hasBase: false, hasContent: false, hasPendingChanges: false),
                      .none, "空笔记不触发任何网络调用")

        r.expectEqual(SummaryOnExit.action(autoUpdateEnabled: true, privacyAccepted: false,
                                           hasBase: false, hasContent: true, hasPendingChanges: true),
                      .none, "**没有隐私同意就一条都不发** —— 这是硬闸门，排在所有其它条件之前")

        r.expectEqual(SummaryOnExit.action(autoUpdateEnabled: false, privacyAccepted: true,
                                           hasBase: false, hasContent: true, hasPendingChanges: true),
                      .none, "用户关掉自动总结就都不生成，包括初始总结")
    }

    // MARK: 5 · 权限被拒的文案（Stage G）

    private static func checkPermissionCopy(_ r: CheckRunner) {
        r.suite("权限被拒 · 只有明确拒绝过才引导去系统设置")

        r.expectNil(PermissionPresentation.copy(for: .microphone, status: .granted),
                    "已授权时没有任何提示界面")

        let notAsked = PermissionPresentation.copy(for: .microphone, status: .notDetermined)
        r.expectNotNil(notAsked)
        r.expect(notAsked?.offersSettings == false,
                 "还没问过时**不**给「打开设置」—— 正确的动作是再问一次，"
                 + "把用户送去设置里找一个还不存在的开关是白跑一趟")
        r.expectEqual(notAsked?.primaryActionTitle, "允许访问")

        let denied = PermissionPresentation.copy(for: .microphone, status: .denied)
        r.expect(denied?.offersSettings == true, "明确被拒才给「打开设置」")
        r.expectEqual(denied?.primaryActionTitle, "打开设置")
        r.expect(denied?.message.contains(PermissionKind.microphone.reason) == true,
                 "解释文案与 Info.plist 的 usage description 同一个说法 —— "
                 + "两套话会让人怀疑哪一句是真的")

        r.expect(PermissionPresentation.shouldRecheckOnForeground(.denied),
                 "从设置回来必须重新检查，否则界面停在「已关闭」，用户会以为设置没生效")
        r.expect(!PermissionPresentation.shouldRecheckOnForeground(.granted),
                 "已授权就不必再查")

        for kind in PermissionKind.allCases {
            r.expect(!kind.reason.isEmpty, "\(kind.rawValue) 有解释文案")
            r.expect(!kind.displayName.isEmpty, "\(kind.rawValue) 有中文名")
        }
    }
}
