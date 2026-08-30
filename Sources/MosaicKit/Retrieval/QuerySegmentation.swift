import Foundation

/// # Query 切分 —— 词法路能不能读懂一句中文
///
/// ## 缺陷是怎么被发现的
///
/// `scenario-v5` 上跑基线，`exact_fact` 拿到 R@1 **0.905**，而
/// `near_duplicate` / `noisy_query` / `contextual_recall` 三类**整类 0.000**。
/// 抽样看实际返回：
///
/// ```
/// query    搜索功能到底什么时候能给内部测试，为什么没上线
/// 期望     T02（搜索功能上线安排）
/// 实际前三 I55（阿莫西林药盒） → D08（家电延保条款） → I54（阿莫西林药盒）
/// ```
///
/// 返回的是纯噪声，说明 **keyword 路一条都没命中**，结果全由弱的本地向量路填满。
///
/// 根因在 `SearchMatcher.tokens(from:)`：它只按**空白**切分。
/// 一句没有空格的中文因此是**一个 token**，而 `TextMatcher.locate` 要求
/// 每个 token 都作为子串出现（AND）—— 于是「整句原样出现在某篇笔记里」
/// 成了命中的必要条件。这在英文上不明显（空格帮了忙），在中文上是**全灭**。
///
/// v4 的评测集看不出这一点，因为它的中文 query 大多是「延期毕业 书面申请」
/// 这种**带空格的关键词组合**。v5 把「真人会怎么打字」写进去之后，它立刻暴露了。
///
/// ## 修法：CJK 连续段切成重叠二元组
///
/// ```
/// 「组会改到周四」 → 组会 · 会改 · 改到 · 到周 · 周四
/// ```
///
/// 二元组是中文检索里最常用的**无分词器**方案：它不需要词典，对未登录词
/// （人名、型号、错别字）天然鲁棒，而中文的信息量本来就集中在相邻两字上。
///
/// ### 为什么不能沿用 AND
///
/// 要求全部二元组都出现，等价于要求整句原样出现 —— 和现在一样严。
/// 所以 CJK 段改为**覆盖率**语义：一段里匹配上的二元组比例 ≥ `minCoverage`
/// 才算这一段命中。拉丁词仍然是 AND（空格已经把它切成了有意义的单位）。
///
/// ### 为什么不是「任意一个二元组命中就算」
///
/// 那会让「的时候」「什么」这类高频虚词把整个语料都召回来。覆盖率把
/// 「大部分说的是同一件事」与「碰巧共用两个字」区分开。
///
/// ## 与「不做 n-gram 索引」那个决定的关系
///
/// `RETRIEVAL_ARCHITECTURE` §26.6 决定**不做倒排 n-gram 索引**，理由是
/// 建索引成本与匹配单位变化。那说的是**索引侧**。这里改的是**查询侧切分**：
/// 不建任何索引、不改存储、不改 chunk，只是把 query 切得更细。
/// 两者是不同的东西，前一个决定不覆盖这一个。
public enum QuerySegmentation: String, Sendable, Equatable, Codable, CaseIterable {
    /// 只按空白切。**中文长 query 会退化成一个 token**，见上文。
    case whitespace
    /// 拉丁按空白，CJK 连续段切重叠二元组 + 覆盖率语义。
    case cjkBigram

    public static let `default` = QuerySegmentation.cjkBigram
}

/// 一个查询词项组。
///
/// 拉丁词各自成组且必须命中；一段 CJK 文字成一组，组内是二元组，
/// 按「至少命中几个」判定（`minimum_should_match` 语义）。
public struct QueryTermGroup: Sendable, Equatable {
    public let terms: [String]
    /// 这一组至少要命中多少个词项才算命中。拉丁组 = `terms.count`（AND）。
    public let minMatched: Int
    /// 这一组是不是 CJK 二元组组。打分时用来做长度补偿。
    public let isBigramGroup: Bool

    public init(terms: [String], minMatched: Int, isBigramGroup: Bool) {
        self.terms = terms
        self.minMatched = max(1, min(minMatched, terms.count))
        self.isBigramGroup = isBigramGroup
    }
}

/// CJK 段的命中门槛策略。
///
/// ## 为什么不是一个固定的覆盖率
///
/// 第一版用「覆盖率 ≥ 0.5」。实测在**长口语 query** 上完全失效：
///
/// ```
/// query   期末那个项目最多几个人一组      →  12 个二元组
/// 正确答案 T54 只命中 期末 · 项目 · 一组  →  覆盖率 0.25 < 0.5，被过滤掉
/// ```
///
/// 而**排名本身是对的** —— T54 命中 3 个、次相关的 T53 命中 2 个、其余 ≤1。
/// 也就是说问题出在**闸门**，不在打分。长 query 里大部分二元组是
/// 「那个」「最多」「几个」这类虚词，它们本来就不该被要求命中。
///
/// 改用 Elasticsearch 的 `minimum_should_match` 语义：
/// **要求命中的个数按比例算，并给一个绝对下限**，比例随 query 变长而自然放宽。
public struct CJKMatchPolicy: Sendable, Equatable, Codable {
    /// 需要命中的二元组比例。
    public var ratio: Double
    /// 绝对下限：至少要命中这么多个。防止「一个二元组碰巧撞上」就算命中。
    public var floor: Int
    /// 中英混排的 query 里，**拉丁词命中之后 CJK 段要不要放宽**。
    ///
    /// 场景：`roialign 那个作业几号截至`。`roialign` 是极强的判别信号，
    /// 而后面那半句全是口语虚词，凑不满 CJK 的门槛 —— 于是整条 query 不命中，
    /// 一个本来一定能找到的答案被口语部分拖没了。
    ///
    /// 打开后，只要有拉丁组命中，CJK 组的门槛降到 1（仍参与打分与覆盖率）。
    /// **默认关闭**：它是不是好，要用 development 扫描说话，不能拍。
    public var latinRelaxesCJK: Bool
    /// 拉丁词之间的 `minimum_should_match` 比例。`nil` = 全部必须命中（AND，旧行为）。
    ///
    /// 为什么需要它：`wheres the midterm now, snell or richards` —— 用户打字时
    /// 少一个撇号、多两个词，AND 语义下**整条 query 不命中**。噪声 query 这一类
    /// 在 development 上因此长期是 0.000。
    ///
    /// 只在拉丁词 ≥ `latinAndBelow` 个时生效：一两个词的 query 本来就该 AND，
    /// 放宽它等于把「精确查两个词」也变成模糊搜索。
    public var latinRatio: Double?
    /// 少于等于这个数量的拉丁词仍然走 AND。
    public var latinAndBelow: Int

    public init(ratio: Double, floor: Int,
                latinRelaxesCJK: Bool = false,
                latinRatio: Double? = nil,
                latinAndBelow: Int = 2) {
        self.ratio = ratio
        self.floor = floor
        self.latinRelaxesCJK = latinRelaxesCJK
        self.latinRatio = latinRatio
        self.latinAndBelow = latinAndBelow
    }

    public func minMatched(termCount: Int) -> Int {
        max(floor, Int((ratio * Double(termCount)).rounded(.up)))
    }

    /// # 生产默认：`ratio 0.15 · floor 3 · latinRelaxesCJK`
    ///
    /// 取值来自 development 上的扫描（`QuerySegmentationSweep`，144 条）：
    ///
    /// | policy | R@1 | 负例克制率 |
    /// |---|---:|---:|
    /// | whitespace（旧） | 0.186 | 100% |
    /// | r=0.34 f=1 | 0.265 | 100% |
    /// | r=0.15 f=3 | 0.310 | 90% |
    /// | r=0.15 f=3 +latin | 0.354 | 90% |
    /// | r=0.15 f=3 +latin L=0.67 | 0.389 | 90% |
    /// | **r=0.15 f=3 +latin L=0.50（选中）** | **0.478** | **90%** |
    /// | r=0.25 f=1 | 0.336 | 80% |
    /// | r=0.15 f=2 +latin | 0.398 | 70% |
    ///
    /// R@1 与负例克制率是**互相交换**的：门槛越松找得越准，但「本来就没有答案」
    /// 的 query 越容易返回点什么。只看 R@1 会把这个代价漏掉。
    ///
    /// 选择依据是一条明写的产品约束：**负例克制率相对当前生产（100%）
    /// 下降不得超过 10pp**。理由是生产里没有相关性下限做兜底 ——
    /// abstention 目前是 `EXPERIMENT_ONLY_NOT_PRODUCTION`（TD-10 未解决），
    /// 「搜什么都有结果」没有第二道防线。
    ///
    /// 在这条约束下取 R@1 最高的一格。三档放宽**都是同代价更优**，
    /// 负例克制率一路都是 90%，R@1 从 0.310 一路到 0.478 ——
    /// 它们不是拿更多误报换来的，而是修掉了「一个词没对上就整条不命中」。
    ///
    /// 更松的两格（0.336 / 0.398）代价是 80% / 70%，留着，
    /// **等 abstention 能上生产再回来取**。
    ///
    /// 三个参数各自的含义：
    ///
    /// - `floor 3`：中文段至少三个相邻字对相同。短 query（≤3 个二元组）由
    ///   `QueryTermGroup` 的 clamp 兜底，不会因为凑不满 3 个而永远不命中。
    /// - `latinRelaxesCJK`：有强判别力的拉丁词命中时，后半句口语不再拖累整条。
    /// - `latinRatio 0.5`：三个以上拉丁词时命中一半即可。它治的是
    ///   `wheres the midterm now, snell or richards` 这类 —— 少一个撇号、
    ///   多两个词，AND 语义下整条不命中。**两个词以内仍然是 AND**
    ///   （`latinAndBelow`），否则「精确查两个词」也会变成模糊搜索。
    public static let `default` = CJKMatchPolicy(ratio: 0.15, floor: 3,
                                                 latinRelaxesCJK: true, latinRatio: 0.5)
}

public extension QuerySegmentation {

    /// 把 query 切成词项组。
    func groups(from query: String,
                policy: CJKMatchPolicy = .default) -> [QueryTermGroup] {
        let rawTokens = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard self == .cjkBigram else {
            return rawTokens
                .map { SearchMatcher.normalize($0) }
                .filter { !$0.isEmpty }
                .map { QueryTermGroup(terms: [$0], minMatched: 1, isBigramGroup: false) }
        }

        // 先看这条 query 里有没有拉丁段。有的话 CJK 段的门槛可以按策略放宽 ——
        // 判断要在建组**之前**做，因为门槛是建组时写进去的。
        let hasLatinRun = policy.latinRelaxesCJK && rawTokens.contains { raw in
            Self.runs(in: raw).contains { $0.kind == .latin && !SearchMatcher.normalize($0.text).isEmpty }
        }

        var groups: [QueryTermGroup] = []
        var latinTerms: [String] = []
        for raw in rawTokens {
            // 一个 token 内部可能中英混排（`CS5330作业`），所以要再按字符类别拆一次。
            for run in Self.runs(in: raw) {
                switch run.kind {
                case .latin:
                    let normalized = SearchMatcher.normalize(run.text)
                    guard !normalized.isEmpty else { continue }
                    latinTerms.append(normalized)
                case .cjk:
                    let chars = Array(SearchMatcher.normalize(run.text))
                    guard chars.count >= 2 else {
                        // 单字：信息量太低，单独成组会把语料全召回来。
                        // 只在它是整个 query 的时候保留（「谁」「钱」这种极短 query）。
                        if chars.count == 1, rawTokens.count == 1, Self.runs(in: raw).count == 1 {
                            groups.append(QueryTermGroup(terms: [String(chars)],
                                                         minMatched: 1, isBigramGroup: false))
                        }
                        continue
                    }
                    var bigrams: [String] = []
                    for i in 0..<(chars.count - 1) {
                        bigrams.append(String(chars[i...(i + 1)]))
                    }
                    // 去重但保持顺序：重复的二元组会让覆盖率分母虚高。
                    var seen = Set<String>()
                    let unique = bigrams.filter { seen.insert($0).inserted }
                    groups.append(QueryTermGroup(
                        terms: unique,
                        minMatched: hasLatinRun ? 1 : policy.minMatched(termCount: unique.count),
                        isBigramGroup: true))
                }
            }
        }

        // 拉丁词收成一组再统一定门槛。
        //
        // 逐词一组（每组 minMatched = 1）等价于 AND —— 任何一组不中，整条不中。
        // 收成一组之后，`minMatched` 才有「几个里中几个」的表达力。
        if !latinTerms.isEmpty {
            var seen = Set<String>()
            let unique = latinTerms.filter { seen.insert($0).inserted }
            let required: Int
            if let ratio = policy.latinRatio, unique.count > policy.latinAndBelow {
                required = max(1, Int((ratio * Double(unique.count)).rounded(.up)))
            } else {
                required = unique.count   // AND，旧行为
            }
            groups.append(QueryTermGroup(terms: unique, minMatched: required,
                                         isBigramGroup: false))
        }
        return groups
    }

    // MARK: 字符段划分

    enum RunKind { case latin, cjk }
    struct Run { let text: String; let kind: RunKind }

    /// 把一个 token 拆成「连续 CJK」与「连续非 CJK」两类段。
    ///
    /// `CS5330作业` → `CS5330`（latin）+ `作业`（cjk）。
    /// 不拆的话，中英混排的 token 会整段掉进 CJK 分支，`CS5330` 被切成
    /// `CS`·`S5`·`53`… 这种毫无意义的二元组。
    static func runs(in token: String) -> [Run] {
        var out: [Run] = []
        var buffer = ""
        var bufferKind: RunKind?
        for ch in token {
            let kind: RunKind = ch.unicodeScalars.contains { ScriptDetection.isHan($0) } ? .cjk : .latin
            if kind != bufferKind, !buffer.isEmpty {
                out.append(Run(text: buffer, kind: bufferKind!))
                buffer = ""
            }
            bufferKind = kind
            buffer.append(ch)
        }
        if !buffer.isEmpty, let bufferKind {
            out.append(Run(text: buffer, kind: bufferKind))
        }
        return out
    }
}
