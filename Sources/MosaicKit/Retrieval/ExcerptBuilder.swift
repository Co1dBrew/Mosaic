import Foundation

/// 开窗后的 excerpt，以及**重新映射到 excerpt 坐标系**的高亮区间。
///
/// 区间必须重映射：原始区间是相对 chunk 全文的，excerpt 是它的一个子串加省略号，
/// 直接沿用会整体错位。
public struct Excerpt: Sendable, Equatable {
    public let text: String
    public let highlights: [TextRange]
    /// 走到了 fallback 链的第几级（1 = 真实命中窗口）。
    public let fallbackLevel: Int

    public init(text: String, highlights: [TextRange], fallbackLevel: Int = 1) {
        self.text = text
        self.highlights = highlights
        self.fallbackLevel = fallbackLevel
    }
}

/// # Matched Excerpt 开窗
///
/// 逐条实现 `design/SEARCH_CONTRACT.md` §2.3 的 W1–W7 与 §2.7 的 fallback 链。
/// 纯函数，没有 I/O、没有状态 —— 每条规则都能单独写一个用例，这是它做成纯函数的
/// 唯一理由。
///
/// | 规则 | 内容 |
/// |---|---|
/// | W1 | 窗口以**第一个命中**为锚点 |
/// | W2 | 左侧约 1/3 预算，右侧约 2/3 —— 向后读比向前读重要 |
/// | W3 | 边界优先吸附最近句读，吸附半径 ±8 字；超出则硬截 |
/// | W4 | **绝不在高亮词内部截断** |
/// | W5 | 未从头开始 → 前置 `…`；未到结尾 → 后置 `…` |
/// | W6 | 全文短于预算 → 全文显示，无省略号 |
/// | W7 | 折叠连续空白与换行为单个空格 |
public enum ExcerptBuilder {

    /// 句读，用于 W3 吸附。中英文都覆盖。
    private static let terminators: Set<Character> = ["。", "！", "？", "；", "，", "…", ".", "!", "?", ";", ",", "\n"]
    /// W3 吸附半径。
    public static let snapRadius = 8
    /// §2.4 高亮渲染上限。
    public static let maxHighlights = 6

    /// 主入口。
    ///
    /// - Parameters:
    ///   - text: chunk 全文。
    ///   - ranges: 命中区间（相对 `text` 的字符偏移）。为空表示纯语义命中，
    ///     此时从开头开窗且不产生高亮。
    ///   - budget: 字符预算。CJK 约 44 字 ≈ 2 行（`SEARCH_CONTRACT` §2.2）。
    public static func build(text: String, ranges: [TextRange], budget: Int = 44) -> Excerpt {
        // W7：先折叠空白，并把区间映射到折叠后的坐标。必须先做，否则后面所有
        // 偏移都是对着原文算的，而展示的是折叠后的文本。
        let (flat, mapped) = collapseWhitespace(text: text, ranges: ranges)
        let chars = Array(flat)

        guard !chars.isEmpty else { return Excerpt(text: "", highlights: [], fallbackLevel: 4) }
        let budget = max(8, budget)

        // W6：全文短于预算 → 原样返回，不加省略号。
        if chars.count <= budget {
            return Excerpt(text: flat, highlights: capped(mapped), fallbackLevel: 1)
        }

        // W1：锚点 = 第一个命中的起点；没有命中就从头开窗。
        let anchor = mapped.first?.start ?? 0

        // W2：左 1/3、右 2/3。
        let left = budget / 3
        var start = max(0, anchor - left)
        var end = min(chars.count, start + budget)
        // 贴到尾部时把窗口往回补满，避免最后一屏只显示半个窗口。
        if end == chars.count { start = max(0, end - budget) }

        // W3：边界吸附句读。
        start = snapStart(chars, from: start)
        end = snapEnd(chars, from: end, limit: start + budget)

        // W4：绝不在高亮内部截断 —— 边界落在某个区间里就向外扩到区间边缘。
        for r in mapped {
            if r.start < start && start < r.end { start = r.start }
            if r.start < end && end < r.end { end = r.end }
        }
        start = max(0, start)
        end = min(chars.count, max(end, start + 1))

        var body = String(chars[start..<end])

        // W5：省略号。计入预算 —— 加了省略号就意味着截断确实发生了。
        let needsPrefix = start > 0
        let needsSuffix = end < chars.count
        if needsPrefix { body = "…" + body }
        if needsSuffix { body += "…" }

        // 区间重映射到 excerpt 坐标；前置省略号占 1 个字符。
        let shift = (needsPrefix ? 1 : 0) - start
        let highlights = mapped.compactMap { r -> TextRange? in
            guard r.start >= start, r.end <= end else { return nil }   // 完全落在窗口内才保留
            return TextRange(start: r.start + shift, end: r.end + shift)
        }

        return Excerpt(text: body, highlights: capped(highlights), fallbackLevel: 1)
    }

    /// §2.7 fallback 链。逐级降级，不跳级。
    ///
    /// 1. 命中窗口 → 2. 笔记首个文字块开头 → 3. AI one_liner → 4. `无预览内容`
    public static func buildWithFallback(matchedText: String?,
                                         ranges: [TextRange],
                                         firstBlockText: String?,
                                         oneLiner: String?,
                                         budget: Int = 44) -> Excerpt {
        if let matchedText, !matchedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return build(text: matchedText, ranges: ranges, budget: budget)
        }
        if let firstBlockText, !firstBlockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var e = build(text: firstBlockText, ranges: [], budget: budget)
            e = Excerpt(text: e.text, highlights: [], fallbackLevel: 2)
            return e
        }
        if let oneLiner, !oneLiner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let e = build(text: oneLiner, ranges: [], budget: budget)
            return Excerpt(text: e.text, highlights: [], fallbackLevel: 3)
        }
        // 第 4 级仍占满行高（由 UI 保证），不塌缩 —— 否则列表节奏会乱。
        return Excerpt(text: "无预览内容", highlights: [], fallbackLevel: 4)
    }

    // MARK: 内部

    /// §2.4：单条 excerpt 最多 6 段高亮，超出的不着色。
    private static func capped(_ ranges: [TextRange]) -> [TextRange] {
        Array(TextMatcher.merge(ranges).prefix(maxHighlights))
    }

    /// W7：把连续空白/换行折叠成单个空格，并同步搬移区间。
    static func collapseWhitespace(text: String, ranges: [TextRange]) -> (String, [TextRange]) {
        let src = Array(text)
        var out: [Character] = []
        out.reserveCapacity(src.count)
        // 原文下标 → 折叠后下标；被吃掉的字符映射到当前输出长度。
        var map = [Int](repeating: 0, count: src.count + 1)

        var i = 0
        var lastWasSpace = false
        while i < src.count {
            map[i] = out.count
            let c = src[i]
            if c.isWhitespace {
                if !lastWasSpace && !out.isEmpty { out.append(" "); lastWasSpace = true }
            } else {
                out.append(c)
                lastWasSpace = false
            }
            i += 1
        }
        // 去掉尾部可能多出来的空格
        while out.last?.isWhitespace == true { out.removeLast() }
        map[src.count] = out.count

        func clamp(_ v: Int) -> Int { min(max(0, v), out.count) }
        let moved = ranges.compactMap { r -> TextRange? in
            let s = clamp(map[min(r.start, src.count)])
            let e = clamp(map[min(r.end, src.count)])
            return e > s ? TextRange(start: s, end: e) : nil
        }
        return (String(out), TextMatcher.merge(moved))
    }

    /// W3：起点向**后**找句读（跳过上一句的尾巴），半径内找不到就用原值。
    private static func snapStart(_ chars: [Character], from start: Int) -> Int {
        guard start > 0 else { return 0 }
        var i = start
        let limit = min(chars.count - 1, start + snapRadius)
        while i <= limit {
            if terminators.contains(chars[i]) { return min(chars.count - 1, i + 1) }
            i += 1
        }
        return start
    }

    /// W3：终点向**前**找句读（在完整一句处收尾），半径内找不到就用原值。
    private static func snapEnd(_ chars: [Character], from end: Int, limit: Int) -> Int {
        guard end < chars.count else { return chars.count }
        var i = min(end, chars.count) - 1
        let floor = max(0, end - snapRadius)
        while i >= floor {
            if terminators.contains(chars[i]) { return min(i + 1, limit) }
            i -= 1
        }
        return end
    }
}
