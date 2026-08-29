import Foundation

/// # 检索能力（`SEARCH_CONTRACT.md` §4.1 的第二个维度）
///
/// 它与 `QueryPhase` **正交**：结果区只看 QueryPhase，状态条只看 Capability。
/// 合并成一个八值枚举会立刻产生「索引建立中但同时在检索」这种无法回答的组合。
///
/// 这是 `IndexState`（工程侧五态）在**用户侧**的投影 —— 两个词表，一个映射，
/// 而不是两套各自演进的状态机。
public enum RetrievalCapability: String, Sendable, Equatable, CaseIterable {
    case full
    case indexBuilding
    case indexRebuilding
    case semanticUnavailable
    case offline

    /// 语义路这次到底能不能用。**keyword 路在任何 capability 下都可用**
    /// （I3），所以这里没有对应的问句。
    public var allowsSemantic: Bool { self == .full }

    /// 由事实推导，不由某处 set。
    ///
    /// - Parameter semanticProviderAvailable: 本机有没有可用的句向量模型。
    ///   没有模型时索引状态可能仍是 `.ready`（没有任何待办），但语义**确实**不可用 ——
    ///   只看 `IndexState` 会在空库上报出 `full`，那是一句假话。
    public static func derive(indexState: IndexState,
                              semanticProviderAvailable: Bool,
                              offline: Bool = false) -> RetrievalCapability {
        if offline { return .offline }
        guard semanticProviderAvailable else { return .semanticUnavailable }
        switch indexState {
        case .ready:       return .full
        case .building:    return .indexBuilding
        case .rebuilding,
             .stale:       return .indexRebuilding
        case .failed:      return .semanticUnavailable
        }
    }
}

/// # 慢通道的门控（`SEARCH_CONTRACT.md` §1.2）
///
/// 极短 query 的语义邻域是噪声，而且要为每次按键付出一次 embedding。低于阈值时
/// keyword 的前缀匹配表现明显更好 —— **这部分是契约，具体字数是 tuning value。**
public enum SemanticGate {

    /// 初值：CJK ≥2 字 · 拉丁 ≥3 字符 · 混合按主语言判定。
    public static let cjkMinimum = 2
    public static let latinMinimum = 3

    public static func shouldRunSemantic(query: String,
                                         cjkMinimum: Int = SemanticGate.cjkMinimum,
                                         latinMinimum: Int = SemanticGate.latinMinimum) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let meaningful = trimmed.filter { !$0.isWhitespace }
        guard !meaningful.isEmpty else { return false }

        // 主语言判定：CJK **严格过半**才按 CJK 的宽阈值算，打平时用更严的拉丁阈值。
        // 取更宽松的那个是错的 —— 那会让「a延」这种两字符噪声 query 也触发一次嵌入。
        let cjkCount = meaningful.filter { $0.isCJK }.count
        let dominatedByCJK = cjkCount * 2 > meaningful.count
        return meaningful.count >= (dominatedByCJK ? cjkMinimum : latinMinimum)
    }
}

private extension Character {
    /// 覆盖 CJK 统一表意文字 + 扩展 A + 兼容表意文字 + 假名。
    var isCJK: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
        }
    }
}

/// 导航载荷的落点（`SEARCH_CONTRACT.md` §3.1）。
///
/// **由检索层给出，不由 UI 猜。** 定不下来就退化为 `.top`，不报错。
public enum SearchAnchor: Sendable, Equatable, Hashable {
    case top
    /// text / image(OCR) / document / link 四类
    case block(String)
    /// audio：进入笔记后需要先展开转写
    case transcript(String)

    public var blockID: String? {
        switch self {
        case .top: return nil
        case let .block(id), let .transcript(id): return id
        }
    }
}

/// 一行搜索结果 —— **以笔记为单位**，不是以 chunk 为单位。
public struct NoteSearchResult: Sendable, Equatable, Identifiable {
    public let noteID: String
    public var id: String { noteID }
    public let rank: Int
    public let anchor: SearchAnchor
    /// 这段 excerpt 的出处，决定行首的来源图标（§2.8）。
    public let source: RetrievalSource
    public let excerpt: Excerpt
    /// 本条是否有字面命中。整页都没有时，列表顶部加一行说明（§2.6）。
    public var hasKeywordHit: Bool { !excerpt.highlights.isEmpty }

    public init(noteID: String, rank: Int, anchor: SearchAnchor,
                source: RetrievalSource, excerpt: Excerpt) {
        self.noteID = noteID
        self.rank = rank
        self.anchor = anchor
        self.source = source
        self.excerpt = excerpt
    }
}

/// # 检索结果 → 搜索结果行
///
/// 把 chunk 级的 `RetrievalOutcome` 收敛成用户看到的一行一笔记。
/// 纯函数，没有 SwiftData、没有 UI —— 所以 §2.5 的选择规则可以逐条单测。
public enum SearchPresentation {

    /// 每篇笔记只显示一段 excerpt。
    ///
    /// **选择规则（§2.5）**：融合后得分最高的 chunk。
    /// 契约里的第 2–4 条（覆盖 term 数 → block order → offset）在当前融合实现下
    /// **不可达** —— `fusedRank` 是一个全序，不存在并列。宁可不写一段永远跑不到的
    /// 分支，也不假装实现了它：真出现并列时，说明融合改了，那时再按契约补。
    ///
    /// - Parameters:
    ///   - budget: excerpt 字符预算（§2.2：CJK 约 44 字 ≈ 2 行）。
    ///   - limit: 结果上限（Q12：Top 50，不分页）。
    public static func rows(from outcome: RetrievalOutcome,
                            budget: Int = 44,
                            limit: Int = 50) -> [NoteSearchResult] {
        var seen = Set<String>()
        var rows: [NoteSearchResult] = []

        // outcome.results 已按 fusedRank 升序 —— 首次遇到某篇笔记时，
        // 手里的就是它得分最高的那个 chunk。
        for result in outcome.results {
            guard !seen.contains(result.ref.noteID) else { continue }
            seen.insert(result.ref.noteID)
            rows.append(NoteSearchResult(
                noteID: result.ref.noteID,
                rank: rows.count + 1,
                anchor: anchor(for: result),
                source: result.source,
                excerpt: ExcerptBuilder.build(text: result.text,
                                              ranges: result.matchedRanges,
                                              budget: budget)
            ))
            if rows.count >= limit { break }
        }
        return rows
    }

    /// 附加「只靠标题 / 标签命中」的笔记。
    ///
    /// 标题与标签是 **lexical signals**，不进语料（§2.8）—— 但它们必须仍然能搜到，
    /// 否则「按标题找笔记」这个既有行为会静默消失。
    ///
    /// 排序上放在内容命中之后：它们没有可比的融合分数，硬塞进榜单中间等于**发明**
    /// 一套相关性。附加顺序由调用方给定（通常是最近更新优先）。
    ///
    /// excerpt 走 fallback 链的第 2 级（笔记开头），**无高亮**（§2.8「标题不高亮」）。
    public static func appendingLexicalMatches(_ rows: [NoteSearchResult],
                                              lexical: [(noteID: String, preview: String)],
                                              budget: Int = 44,
                                              limit: Int = 50) -> [NoteSearchResult] {
        var out = rows
        var seen = Set(rows.map(\.noteID))
        for match in lexical {
            guard out.count < limit, !seen.contains(match.noteID) else { continue }
            seen.insert(match.noteID)
            out.append(NoteSearchResult(
                noteID: match.noteID,
                rank: out.count + 1,
                anchor: .top,
                source: .text,
                excerpt: ExcerptBuilder.buildWithFallback(matchedText: nil,
                                                          ranges: [],
                                                          firstBlockText: match.preview,
                                                          oneLiner: nil,
                                                          budget: budget)
            ))
        }
        return out
    }

    /// §2.6：整页零字面命中时，列表顶部加一行说明。
    ///
    /// **部分有部分没有时不显示** —— 混合是正常状态，不需要解释。
    public static func needsSemanticOnlyNotice(_ rows: [NoteSearchResult]) -> Bool {
        !rows.isEmpty && rows.allSatisfy { !$0.hasKeywordHit }
    }

    /// 一行结果的朗读文本（backlog 6.6）。
    ///
    /// **顺序是契约的一部分**：标题 → 来源 → 命中片段 → 文件夹 → 时间。
    /// 视觉上来源是一个 20pt 的图标、时间是右下角一行小字，读屏用户拿不到这种
    /// 空间线索 —— 所以顺序必须由这里给定，而不是由 SwiftUI 的默认遍历顺序决定
    /// （默认顺序是布局顺序：标题、图标、片段、文件夹、时间恰好还对，
    /// 但图标没有标签，会被读成一个无意义的元素，而且行会被拆成五个可聚焦项）。
    ///
    /// 高亮区间**不进入朗读**：对比式前景高亮是视觉手段，读出「命中」两个字
    /// 只会打断句子。
    public static func accessibilityLabel(row: NoteSearchResult,
                                          title: String,
                                          folderName: String?,
                                          relativeTime: String) -> String {
        var parts: [String] = [title]
        if let source = sourceLabel(row.source) { parts.append(source) }
        let excerpt = row.excerpt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !excerpt.isEmpty { parts.append(excerpt) }
        if let folderName, !folderName.isEmpty { parts.append(folderName) }
        parts.append(relativeTime)
        return parts.joined(separator: "，")
    }

    /// 出处的朗读名。**纯文本命中没有出处标签** —— 它是默认形态，
    /// 读出「文字」只是噪声。用户侧词表照旧：不出现 embedding / 向量 / chunk。
    public static func sourceLabel(_ source: RetrievalSource) -> String? {
        switch source {
        case .text:       return nil
        case .transcript: return "来自录音转写"
        case .ocr:        return "来自图片文字"
        case .extracted:  return "来自文档"
        case .link:       return "来自链接"
        }
    }

    private static func anchor(for result: RetrievalResult) -> SearchAnchor {
        switch result.source {
        case .transcript: return .transcript(result.ref.blockID)
        case .text, .ocr, .extracted, .link: return .block(result.ref.blockID)
        }
    }
}
