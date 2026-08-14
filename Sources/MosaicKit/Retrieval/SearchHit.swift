import Foundation

/// 字符区间（半开 `[start, end)`），单位是 **Character**，不是 UTF-8 字节。
///
/// 中文一个字在 UTF-8 里占 3 字节，用字节偏移做高亮会切碎汉字。所有偏移在整条
/// 管线里统一按 Character 计。
public struct TextRange: Sendable, Equatable, Hashable, Codable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = max(start, end)
    }

    public var length: Int { end - start }
    public var isEmpty: Bool { end <= start }
    public func contains(_ i: Int) -> Bool { i >= start && i < end }
    public func overlaps(_ o: TextRange) -> Bool { start < o.end && o.start < end }
}

/// # IG-2 — 一次关键词命中
///
/// 取代原来 `matches(...) -> Bool` 的返回值。`Bool` 丢掉了三样东西，而这三样正好
/// 是 Goal 1 全部需要的：
///
/// | 丢掉的 | 谁需要它 |
/// |---|---|
/// | **命中位置** | Matched Excerpt 开窗 + 对比式高亮 |
/// | **归属哪个 block** | Search Result → Note 的 scroll anchor |
/// | **分数** | 排名，以及与 vector 路做 RRF 融合 |
///
/// 没有这三样，`SEARCH_CONTRACT` 里的 Matched Excerpt 一行都实现不了。
public struct KeywordHit: Sendable, Equatable {
    public let chunkID: String
    public let ref: BlockRef
    public let source: RetrievalSource
    /// chunk 的全文，excerpt 从这里开窗。
    public let text: String
    /// 命中区间，已按 start 升序合并去重。
    public let ranges: [TextRange]
    public let score: Double

    public init(chunkID: String, ref: BlockRef, source: RetrievalSource,
                text: String, ranges: [TextRange], score: Double) {
        self.chunkID = chunkID
        self.ref = ref
        self.source = source
        self.text = text
        self.ranges = ranges
        self.score = score
    }
}

/// 在一段文本里定位 query 词的所有出现位置。
///
/// ## 分词口径（中英文）
///
/// **按空白切分，然后做子串定位。** 刻意**不**引入词典分词，也不做 CJK 二元组：
///
/// - 中文子串匹配天然可用 —— 「延期」在「延期毕业」里就是一个子串，不需要词典。
/// - 引入二元组会让 `SEARCH_CONTRACT` §2.6 的前提失效：一句自然语言 query
///   （「我之前问学校能不能晚一点毕业的事情」）**应该** keyword 零命中、全部交给
///   语义路，这正是 24 屏「全部为相关结果」要展示的东西。二元组会让它蒙对几条，
///   把一个清晰的产品状态变成一团糊。
/// - 与既有 `SearchMatcher.matches` 的语义**完全一致**，所以线上搜索行为不变。
///
/// 代价是承认的：keyword 路对长句无能为力。那本来就是 vector 路的职责。
public enum TextMatcher {

    /// 归一化：大小写 / 变音符 / 全角半角。与 `SearchMatcher.normalize` 同一套。
    ///
    /// - Important: 归一化必须**保持字符数不变**，否则偏移会错位。
    ///   `.folding` 对上述三类是 1:1 的；这里额外断言，防止将来有人加进会改变
    ///   长度的选项（比如把 "ﬁ" 拆成 "fi"）。
    public static func normalizedForOffsets(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                               locale: nil)
        return folded.count == s.count ? folded : s.lowercased()
    }

    /// 找出 `tokens` 在 `text` 中的全部出现位置。
    ///
    /// - Returns: 合并后的区间（按 start 升序，互不重叠），以及每个 token 的出现次数。
    ///   任何一个 token 完全没出现 → 返回 `nil`（AND 语义，与既有匹配器一致）。
    public static func locate(tokens: [String], in text: String) -> (ranges: [TextRange], counts: [Int])? {
        guard !tokens.isEmpty else { return nil }
        let hayChars = Array(normalizedForOffsets(text))
        guard !hayChars.isEmpty else { return nil }

        var all: [TextRange] = []
        var counts: [Int] = []

        for token in tokens {
            let needle = Array(normalizedForOffsets(token))
            guard !needle.isEmpty, needle.count <= hayChars.count else { return nil }
            var found = 0
            var i = 0
            while i + needle.count <= hayChars.count {
                if hayChars[i] == needle[0], Array(hayChars[i..<(i + needle.count)]) == needle {
                    all.append(TextRange(start: i, end: i + needle.count))
                    found += 1
                    i += needle.count          // 不重叠计数
                } else {
                    i += 1
                }
            }
            guard found > 0 else { return nil }   // AND：缺一个就整体不命中
            counts.append(found)
        }

        return (merge(all), counts)
    }

    /// 合并重叠 / 相邻的区间，避免高亮时出现相互覆盖的片段。
    public static func merge(_ ranges: [TextRange]) -> [TextRange] {
        guard !ranges.isEmpty else { return [] }
        let sorted = ranges.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        var out: [TextRange] = [sorted[0]]
        for r in sorted.dropFirst() {
            let last = out[out.count - 1]
            if r.start <= last.end {
                out[out.count - 1] = TextRange(start: last.start, end: max(last.end, r.end))
            } else {
                out.append(r)
            }
        }
        return out
    }
}
