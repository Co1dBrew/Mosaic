import Foundation

/// 导航载荷（`SEARCH_CONTRACT.md` §3.1）。
///
/// anchor **由检索层给出，不由 UI 猜**；定不下来就退化为 `.top`，不报错、不提示。
public struct SearchDestination: Sendable, Equatable, Identifiable {
    public let noteID: String
    public let anchor: SearchAnchor

    public var id: String {
        switch anchor {
        case .top: return "\(noteID)|top"
        case let .block(b): return "\(noteID)|block|\(b)"
        case let .transcript(b): return "\(noteID)|transcript|\(b)"
        }
    }

    public init(noteID: String, anchor: SearchAnchor) {
        self.noteID = noteID
        self.anchor = anchor
    }

    public init(row: NoteSearchResult) {
        self.init(noteID: row.noteID, anchor: row.anchor)
    }
}

/// # Result → Note 落点（`SEARCH_CONTRACT.md` §3.2–§3.4 · backlog 5.10）
///
/// 契约里的时序与几何都是**具体数字**，所以它们该是可被断言的常量与纯函数，
/// 而不是散落在 View 里的字面量 —— 散落的字面量没有办法证明「实现符合契约」，
/// 只能靠人去比对文档。
public enum SearchLanding {

    // MARK: 时序（§3.3）

    /// push 转场**完成后**再等这么久才开始高亮。转场中闪高亮会被动画吃掉。
    public static let highlightDelay: Double = 0.15
    /// 全不透明保持时长。
    public static let highlightHold: Double = 2.0
    /// 正常淡出。
    public static let highlightFade: Double = 0.4
    /// 被用户打断时的淡出 —— **更快**。高亮是提示，不是障碍。
    public static let interruptFade: Double = 0.2
    /// 总计 2.4s（延迟不计入）。
    public static var highlightTotal: Double { highlightHold + highlightFade }

    // MARK: 几何（§3.3 / §3.4）

    /// block 外接矩形的外扩。
    public static let highlightPadding: Double = 8
    /// `radius/md`
    public static let highlightCornerRadius: Double = 12
    /// `.top` 落点时顶部留出的内边距。
    public static let topInset: Double = 88
    /// 超过可视区这个比例就改用 `.top` 落点。
    public static let centerThreshold: Double = 0.5

    /// 滚动落点。
    ///
    /// - `.center`：目标 block 高度 ≤ 50% 可视区 —— 居中最容易被一眼看到。
    /// - `.top(unitY:)`：更高的 block 居中会把开头顶出屏幕，所以改为顶部对齐并留
    ///   `topInset` 内边距。
    ///
    /// `unitY` 是给 `ScrollViewReader.scrollTo(_:anchor:)` 的锚点：SwiftUI 把
    /// **目标视图**上的这个比例点与**可视区**上的同一个比例点对齐，于是
    /// `offset = origin + y·H_view − y·H_viewport`。要让 block 顶部落在距顶部
    /// `topInset` 处，需要 `y·(H_view − H_viewport) = −topInset`，即
    /// `y = topInset / (H_viewport − H_view)`。
    ///
    /// block 比可视区还高时这个式子无解（分母 ≤ 0）—— 那种情况下顶部对齐
    /// （`y = 0`）就是能给出的最好结果。
    public enum ScrollTarget: Sendable, Equatable {
        case center
        case top(unitY: Double)
    }

    public static func scrollTarget(blockHeight: Double,
                                    viewportHeight: Double,
                                    topInset: Double = SearchLanding.topInset) -> ScrollTarget {
        guard viewportHeight > 0, blockHeight > 0 else { return .center }
        if blockHeight <= viewportHeight * centerThreshold { return .center }
        let denominator = viewportHeight - blockHeight
        guard denominator > 0 else { return .top(unitY: 0) }
        return .top(unitY: min(1, max(0, topInset / denominator)))
    }

    // MARK: 行为分派（§3.2）

    /// 是否需要滚动。**Title 命中不滚动、不高亮** —— 落点就是笔记顶部。
    public static func requiresScroll(_ anchor: SearchAnchor) -> Bool { anchor.blockID != nil }

    /// 是否要先展开转写。展开会改变布局高度，所以必须
    /// `expand → 等一次 layout pass → scroll`，不可同帧执行（§3.4）。
    public static func requiresTranscriptExpansion(_ anchor: SearchAnchor) -> Bool {
        if case .transcript = anchor { return true }
        return false
    }

    /// 是否要临时高亮。与 `requiresScroll` 同一条件：不滚动的落点也没有可高亮的 block。
    public static func requiresHighlight(_ anchor: SearchAnchor) -> Bool { requiresScroll(anchor) }

    /// anchor 指向的 block 已经不在笔记里（被删了 / 索引 stale）→ 退化为 `.top`，
    /// **不报错、不提示**（§3.4）。用户的意图是「找到这条笔记」，而笔记还在。
    public static func resolve(_ anchor: SearchAnchor, existingBlockIDs: Set<String>) -> SearchAnchor {
        guard let blockID = anchor.blockID else { return .top }
        return existingBlockIDs.contains(blockID) ? anchor : .top
    }
}
