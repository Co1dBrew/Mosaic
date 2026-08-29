import SwiftUI
import Observation
import MosaicKit

/// # Result → Note 落点的执行者（backlog 5.10 · `SEARCH_CONTRACT.md` §3）
///
/// 几何与时序的**数值**在内核 `SearchLanding` 里（可断言）；这里只负责把它们
/// 按契约的顺序执行出来，以及处理三件 SwiftUI 特有的事：
///
/// 1. **转写要先展开，再等一次 layout pass，才能滚动。** 展开改变布局高度，
///    同帧执行会滚到展开前的位置上。
/// 2. **滚动不加动画。** 在 push 转场之前 / 之中完成定位，笔记页出现时**已经**
///    停在目标位置。push 转场叠加 scroll 动画会产生明显 jank，而且用户会看到内容
///    「飞过」，反而丢失定位感。
/// 3. **可中断。** 用户滚动 / 点击 / 开始编辑 → 立即以更快的速度淡出。
///    高亮是提示，不是障碍。
@Observable
@MainActor
final class SearchLandingController {

    /// 解析之后的落点。block 已被删除时它是 `.top`（§3.4：不报错、不提示）。
    private(set) var anchor: SearchAnchor = .top
    /// 当前高亮的 block。`nil` = 没有高亮。
    private(set) var highlightedBlockID: String?
    /// 高亮不透明度。淡出是**这一个值**的动画，不做缩放、不做描边（§3.3）。
    private(set) var highlightOpacity: Double = 0
    /// 需要展开转写的那个 block（音频命中）。
    private(set) var expandedTranscriptBlockID: String?
    /// 已经落过一次点。`onAppear` 可能多次触发，但落点只做一次 ——
    /// 每次视图重新出现都重滚一遍等于把用户的滚动位置吞掉。
    private(set) var hasLanded = false

    private var timeline: Task<Void, Never>?

    /// 进入笔记时调用。
    ///
    /// - Parameter existingBlockIDs: 笔记当前真实存在的 block。anchor 指向的 block
    ///   已经不在了（被删 / 索引 stale）就退化为 `.top`。
    /// - Parameter scroll: 真正执行滚动的闭包，由 View 提供（它持有
    ///   `ScrollViewProxy` 与可视区高度）。
    func land(anchor requested: SearchAnchor,
              existingBlockIDs: Set<String>,
              scroll: @escaping (String) -> Void) {
        guard !hasLanded else { return }
        hasLanded = true

        let resolved = SearchLanding.resolve(requested, existingBlockIDs: existingBlockIDs)
        anchor = resolved
        guard let blockID = resolved.blockID, SearchLanding.requiresScroll(resolved) else { return }

        timeline?.cancel()
        // 闭包里对属性的写入一律显式 `self.` —— Swift 6 语言模式下隐式捕获是错误，
        // 现在只是警告。这里的写入都在 `@MainActor` 上，加 `self.` 只是把捕获语义
        // 写明白，不改变任何行为。
        timeline = Task { @MainActor [weak self] in
            guard let self else { return }

            // 1 · 音频命中：先展开转写。
            if SearchLanding.requiresTranscriptExpansion(resolved) {
                self.expandedTranscriptBlockID = blockID
                // 等一次 layout pass。`Task.yield()` 只让出当前 actor 的一个调度点，
                // 不保证 SwiftUI 已经重新布局过 —— 所以这里等一帧的时间。
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
            guard !Task.isCancelled else { return }

            // 2 · 定位。**无动画**（由 scroll 闭包保证）。
            scroll(blockID)

            // 3 · 高亮：转场完成后 +0.15s 才开始。
            try? await Task.sleep(nanoseconds: UInt64(SearchLanding.highlightDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.highlightedBlockID = blockID
            self.highlightOpacity = 1

            // 4 · 保持 2.0s → 0.4s ease-out 淡出。
            try? await Task.sleep(nanoseconds: UInt64(SearchLanding.highlightHold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: SearchLanding.highlightFade)) {
                self.highlightOpacity = 0
            }
            try? await Task.sleep(nanoseconds: UInt64(SearchLanding.highlightFade * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.highlightedBlockID = nil
        }
    }

    /// 用户滚动 / 点击 / 开始编辑。**立即**以 0.2s 淡出。
    ///
    /// 幂等：手势会连续触发很多次，第二次之后不该重启一遍淡出动画。
    func interrupt() {
        guard highlightedBlockID != nil || timeline != nil else { return }
        timeline?.cancel()
        timeline = nil
        guard highlightOpacity > 0 else { highlightedBlockID = nil; return }
        withAnimation(.easeOut(duration: SearchLanding.interruptFade)) {
            highlightOpacity = 0
        }
        let blockID = highlightedBlockID
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SearchLanding.interruptFade * 1_000_000_000))
            guard let self, self.highlightedBlockID == blockID else { return }
            self.highlightedBlockID = nil
        }
    }

    func isHighlighted(_ blockID: String) -> Bool { highlightedBlockID == blockID }
    func expandsTranscript(_ blockID: String) -> Bool { expandedTranscriptBlockID == blockID }
}

/// block 级临时高亮：外接矩形 + 8pt 外扩，填充 `accent/blue-bg`，圆角 12。
/// **无描边、无阴影、无缩放**（§3.3）。
///
/// 正文内**不注入 term 级高亮**（§3.3.1）：笔记正文是可编辑表面，
/// 往可编辑文本里塞高亮 range 会与编辑器的 attributed text 状态、光标、撤销栈冲突。
struct LandingHighlight: ViewModifier {
    let isActive: Bool
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: SearchLanding.highlightCornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .padding(-SearchLanding.highlightPadding)
                    .opacity(isActive ? opacity : 0)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func landingHighlight(isActive: Bool, opacity: Double) -> some View {
        modifier(LandingHighlight(isActive: isActive, opacity: opacity))
    }
}
