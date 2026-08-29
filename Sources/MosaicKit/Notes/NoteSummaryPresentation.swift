import Foundation

/// # 笔记页顶部 AI 摘要条的状态（`UI_REDESIGN.md` v2 §3.4）
///
/// 收起态是一条 44pt 横条，六种取值。把它写成一个纯函数而不是几个
/// `if isLoading … else if error …` 的嵌套，是因为其中**两档最容易被漏掉**：
///
/// - 「无摘要 · 有内容」要显示一句灰色的、**不可点**的告知（退出后会自动生成），
///   而不是一个「生成总结」按钮 —— v2 把生成时机统一到退出，
///   页面里再放一个生成按钮就又变回两套机制。
/// - 「无摘要 · 内容为空」整条隐藏。新建笔记的第一秒就处于这一档。
public enum NoteSummaryBarState: Sendable, Equatable {
    /// 整条不显示。
    case hidden
    /// 有内容但还没有摘要。**纯告知，不可点。**
    case pending
    case generating
    /// `opensSettings` = 是配置类错误（缺 Key / Base URL 不对），才给「去设置」。
    case failed(message: String, opensSettings: Bool)
    case ready(oneLiner: String, hasUnread: Bool)

    /// 收起态那一行能不能展开。失败态可以点（要看重试按钮），pending 不能。
    public var isExpandable: Bool {
        switch self {
        case .ready: return true
        case .hidden, .pending, .generating, .failed: return false
        }
    }
}

public enum NoteSummaryPresentation {

    public static func barState(hasBase: Bool,
                                oneLiner: String,
                                noteIsEmpty: Bool,
                                isGenerating: Bool,
                                errorMessage: String?,
                                errorIsConfiguration: Bool,
                                hasUnreadUpdates: Bool) -> NoteSummaryBarState {
        if isGenerating { return .generating }
        if let errorMessage, !errorMessage.isEmpty {
            return .failed(message: errorMessage, opensSettings: errorIsConfiguration)
        }
        if hasBase {
            let trimmed = oneLiner.trimmingCharacters(in: .whitespacesAndNewlines)
            // 有 base 但一句话是空的（模型返回了空串）：退回到 pending 的文案比
            // 显示一条空横条好 —— 空横条看起来像加载卡住了。
            guard !trimmed.isEmpty else { return .pending }
            return .ready(oneLiner: trimmed, hasUnread: hasUnreadUpdates)
        }
        return noteIsEmpty ? .hidden : .pending
    }

    /// 收起态那一行的文字。**用户侧文案集中在这里**，与状态判断放在一起，
    /// 避免 View 里再写一遍条件。
    public static func collapsedText(_ state: NoteSummaryBarState) -> String? {
        switch state {
        case .hidden:                   return nil
        case .pending:                  return "退出后将自动生成总结"
        case .generating:               return "AI 正在总结…"
        case .failed(let message, _):   return message
        case .ready(let oneLiner, _):   return oneLiner
        }
    }
}

// MARK: - 退出时的总结时机（§3.10）

/// 退出笔记页时**要不要**生成，以及生成哪一种。
///
/// v2 的关键改动：`ensureBaseIfNeeded` 从 `onAppear` 移到退出流程，
/// 与更新总结走同一个判定入口。用户只需要理解**一条**规则：
/// 「写完退出，AI 就会总结」。
///
/// 副作用是**只是点进去看一眼不会花钱** —— 比旧行为更省。
public enum SummaryOnExit {

    public enum Action: Sendable, Equatable {
        case none
        /// 还没有初始总结 → 生成它。
        case generateBase
        /// 已有初始总结且有实质变更 → 追加一条更新记录。
        case appendUpdate
    }

    /// - Parameter autoUpdateEnabled: 设置里的「内容变更后自动追加更新总结」。
    /// - Parameter privacyAccepted: 首次 AI 隐私同意。**没有同意就一条都不发。**
    /// - Parameter hasContent: 笔记里有没有可总结的内容。空笔记不该触发一次网络调用。
    /// - Parameter hasPendingChanges: `SummaryService` 的快照 diff 判定。
    public static func action(autoUpdateEnabled: Bool,
                              privacyAccepted: Bool,
                              hasBase: Bool,
                              hasContent: Bool,
                              hasPendingChanges: Bool) -> Action {
        // 隐私同意是硬闸门，排在最前 —— 它管的是「内容能不能离开设备」，
        // 与用户想不想要自动总结是两件事。
        guard privacyAccepted, autoUpdateEnabled, hasContent else { return .none }
        if !hasBase { return .generateBase }
        return hasPendingChanges ? .appendUpdate : .none
    }
}
