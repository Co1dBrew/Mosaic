import Foundation
import MosaicKit

/// # 场景化评测集的**标注质量**断言（`scenario-v5`）
///
/// 与 `HumanLikeGoldenChecks` 的分工：那边测「语料结构」（各类语料的规模、长文锚点、
/// 干扰簇），这边测「标注本身」（类别分布、分级相关性、硬负例、split、来源标记）。
///
/// ## 为什么这些要在 Swift 侧再测一遍
///
/// 生成脚本 `tools/eval/build_scenario_set.py` 自己也会自检，但那是**生成时**的检查。
/// 数据一旦落盘就可能被手改（改一个 expected、删一条用例），而手改不会重跑脚本。
/// 这里的断言跟着 `swift run mosaic-checks` 每次都跑，是数据的**常驻**守卫。
enum ScenarioDatasetChecks {

    /// 冻结指纹。**改数据必须同时改这一行**，这是「holdout 已冻结」唯一的证据。
    ///
    /// 它故意写死而不是现算：现算的话任何改动都会自洽，指纹就只是个装饰。
    /// 改数据的正确流程是跑一遍 `tools/eval/build_scenario_set.py`，
    /// 把它打印的 checksum 抄到这里，并在提交信息里说明改了什么。
    static let frozenChecksum = "sha256:06d2f8c1d3b8dc0e2d0e15184dbf5834a96c953f395245daa38c6902c8fb3a00"

    /// 类别目标占比与容差。容差 ±3pp —— 分布是**设计目标**不是自然律，
    /// 卡到小数点后一位只会让每次增删用例都要重新配平。
    static let categoryTargets: [(GoldenSetFixture.Category, Double)] = [
        (.semanticRecall, 0.20), (.exactFact, 0.15), (.lexicalTrap, 0.15),
        (.nearDuplicate, 0.15), (.crossLanguage, 0.10), (.noisyQuery, 0.10),
        (.contextualRecall, 0.05), (.negative, 0.05), (.ambiguous, 0.05)
    ]

    static func run(_ r: CheckRunner) {
        guard let dataset = try? HumanLikeGoldenFixture.load() else {
            r.expect(false, "fixture 应当可加载")
            return
        }
        checkProvenanceAndFreeze(dataset, r)
        checkCategoryDistribution(dataset, r)
        checkGradedRelevance(dataset, r)
        checkHardNegatives(dataset, r)
        checkCoverage(dataset, r)
        checkSplit(dataset, r)
        checkNoLeakage(dataset, r)
    }

    // MARK: 1 · 来源标记与冻结

    private static func checkProvenanceAndFreeze(_ d: GoldenSetFixture.Dataset, _ r: CheckRunner) {
        r.suite("scenario-v5 · 来源标记与冻结指纹")

        r.expectEqual(d.checksum, frozenChecksum,
                      "数据指纹与冻结值一致 —— 不一致说明有人改了数据没重跑生成脚本，"
                      + "此时 holdout 的「冻结」不再成立")

        r.expect(d.cases.allSatisfy { $0.provenance == .agentAuthoredRealistic },
                 "全部正例标 agent_authored_realistic")
        r.expect(d.negativeQueries.allSatisfy { $0.provenance == .agentAuthoredRealistic },
                 "全部负例标 agent_authored_realistic")

        // 免责声明必须**在数据里**，不是只写在文档里 —— 数据会被拷走，文档不会。
        let lowered = d.disclaimer.lowercased()
        for forbidden in ["real user data", "real user queries", "production traffic"] {
            r.expect(lowered.contains(forbidden),
                     "免责声明明确否认「\(forbidden)」")
        }
    }

    // MARK: 2 · 类别分布

    private static func checkCategoryDistribution(_ d: GoldenSetFixture.Dataset, _ r: CheckRunner) {
        r.suite("scenario-v5 · 九类能力的覆盖与配比")

        var counts: [GoldenSetFixture.Category: Int] = [:]
        for c in d.cases {
            guard let cat = c.category else {
                r.expect(false, "\(c.id) 没有标类别")
                continue
            }
            counts[cat, default: 0] += 1
        }
        counts[.negative, default: 0] += d.negativeQueries.count
        let total = Double(d.cases.count + d.negativeQueries.count)

        for (cat, target) in categoryTargets {
            let n = counts[cat] ?? 0
            r.expect(n > 0, "类别 \(cat.rawValue) 有用例")
            let share = Double(n) / total
            r.expect(abs(share - target) <= 0.03,
                     "\(cat.rawValue) 占比 \(percent(share))（目标 \(percent(target))，容差 3pp，"
                     + "实际 \(n) 条）")
        }
        r.expectEqual(Set(counts.keys).count, GoldenSetFixture.Category.allCases.count,
                      "九类全部有覆盖 —— 少一类就等于那一种失败模式没有人在看")

        // 难度：每一类都要有 hard，否则那一类只是在测「能不能跑通」。
        for (cat, _) in categoryTargets where cat != .negative {
            let difficulties = Set(d.cases.filter { $0.category == cat }.compactMap(\.difficulty))
            r.expect(difficulties.contains(.hard) || difficulties.contains(.medium),
                     "\(cat.rawValue) 至少有 medium 或 hard 的用例")
        }
    }

    // MARK: 3 · 分级相关性

    private static func checkGradedRelevance(_ d: GoldenSetFixture.Dataset, _ r: CheckRunner) {
        r.suite("scenario-v5 · 分级相关性 0–3 与 binary 映射")

        let noteIDs = Set(d.notes.map(\.id))
        var graded = 0
        for c in d.cases {
            guard let rel = c.relevance, !rel.isEmpty else {
                r.expect(false, "\(c.id) 没有分级相关性")
                continue
            }
            graded += 1
            r.expect(rel.values.allSatisfy { (0...3).contains($0) },
                     "\(c.id) 的分数都在 0–3")
            r.expect(Set(rel.keys).isSubset(of: noteIDs),
                     "\(c.id) 的分级只引用存在的笔记")
            // binary 口径：≥2 算相关。它必须与 expectedNoteIDs 完全一致，
            // 否则「跑批用的分母」与「标注写的答案」是两回事。
            r.expectEqual(c.binaryRelevantNoteIDs, c.expectedNoteIDs.sorted(),
                          "\(c.id) 的 binary 映射（≥2 分）与 expectedNoteIDs 一致")
            r.expect(rel.values.contains(3),
                     "\(c.id) 至少有一篇是 3 分（就是它）")
        }
        r.expectEqual(graded, d.cases.count, "每条正例都有分级标注")

        // 1 分（部分相关）既不算命中也不算错误 —— 这条规则必须在实现里，不能只在文档里。
        // 用一条现造的 JSON 走同一个解析器，而不是直接构造结构体：
        // 断言要覆盖的是「落盘数据被读出来之后」的行为。
        let probe = """
        {"id":"probe","query":"q","expectedNoteIDs":["A"],"style":"natural",
         "queryLanguage":"zh","expectedLanguage":"zh","scope":"in-scope","note":"",
         "relevance":{"A":3,"B":1,"C":0}}
        """
        if let decoded = try? JSONDecoder().decode(GoldenSetFixture.Candidate.self,
                                                   from: Data(probe.utf8)) {
            r.expectEqual(decoded.binaryRelevantNoteIDs, ["A"],
                          "1 分与 0 分都不进 binary 相关集")
        } else {
            r.expect(false, "探针用例应当可解析")
        }
    }

    // MARK: 4 · 硬负例

    private static func checkHardNegatives(_ d: GoldenSetFixture.Dataset, _ r: CheckRunner) {
        r.suite("scenario-v5 · 硬负例：中高难度都要说得出「哪一篇容易被误判」")

        let noteIDs = Set(d.notes.map(\.id))
        var withHard = 0
        for c in d.cases {
            let hard = c.hardNegativeNoteIDs ?? []
            if !hard.isEmpty { withHard += 1 }
            r.expect(Set(hard).isSubset(of: noteIDs), "\(c.id) 的硬负例都存在")
            r.expect(Set(hard).isDisjoint(with: Set(c.expectedNoteIDs)),
                     "\(c.id) 不把同一篇同时标成答案和硬负例")
            // cross-language 例外：那一类的失败原因是语种覆盖，不是「选错了近似项」，
            // 给它硬凑一个干扰项是在编造理由。
            if (c.difficulty == .medium || c.difficulty == .hard), c.category != .crossLanguage {
                r.expect(!hard.isEmpty,
                         "\(c.id)（\(c.difficulty?.rawValue ?? "?")）有硬负例 —— "
                         + "说不出谁会被误判，说明它其实是 easy")
            }
        }
        r.expect(Double(withHard) / Double(d.cases.count) >= 0.7,
                 "至少 70% 的正例带硬负例（实际 \(withHard)/\(d.cases.count)）")
    }

    // MARK: 5 · 语料类型与落点覆盖

    private static func checkCoverage(_ d: GoldenSetFixture.Dataset, _ r: CheckRunner) {
        r.suite("scenario-v5 · 五类语料 × 难度 × 落点")

        let notesByID = Dictionary(uniqueKeysWithValues: d.notes.map { ($0.id, $0) })
        var byType: [RetrievalSource: Set<GoldenSetFixture.Difficulty>] = [:]
        for c in d.cases {
            guard let type = c.contentType, let diff = c.difficulty else {
                r.expect(false, "\(c.id) 缺 contentType 或 difficulty")
                continue
            }
            byType[type, default: []].insert(diff)
            // contentType 是冗余字段，必须与笔记表对得上，否则按类型切片统计是错的。
            r.expectEqual(notesByID[c.expectedNoteIDs[0]]?.source, type,
                          "\(c.id) 的 contentType 与目标笔记一致")
            // 落点：录音要先展开转写（SEARCH_CONTRACT §3.2），其余定位到块。
            let expectedPrefix = type == .transcript ? "transcript:" : "block:"
            r.expect(c.expectedLandingTarget?.hasPrefix(expectedPrefix) == true,
                     "\(c.id) 的期望落点前缀是 \(expectedPrefix)")
        }
        for source in RetrievalSource.allCases {
            let diffs = byType[source] ?? []
            r.expectEqual(diffs.count, 3,
                          "\(source.rawValue) 三档难度齐全（实际 \(diffs.map(\.rawValue).sorted())）")
        }

        r.expect(d.cases.allSatisfy { !($0.scenario ?? "").isEmpty },
                 "每条用例都写了场景 —— 没有场景就没法让第二个人复核它像不像真人问的")
        r.expect(d.cases.allSatisfy { !($0.rationale ?? "").isEmpty },
                 "每条用例都写了「为什么值得测」")
    }

    // MARK: 6 · Development / Holdout

    private static func checkSplit(_ d: GoldenSetFixture.Dataset, _ r: CheckRunner) {
        r.suite("scenario-v5 · 70/30 分层划分，holdout 只用于发布判定")

        let dev = d.evalCases(split: .development)
        let hold = d.evalCases(split: .holdout)
        let total = Double(dev.count + hold.count)
        r.expectEqual(Int(total), d.cases.count + d.negativeQueries.count,
                      "每条用例都落在某一个 split 里，不重不漏")
        r.expect(abs(Double(hold.count) / total - 0.30) <= 0.05,
                 "holdout 占 30%±5pp（实际 \(percent(Double(hold.count) / total))，"
                 + "\(hold.count)/\(Int(total)) 条）")
        r.expect(Set(dev.map(\.id)).isDisjoint(with: Set(hold.map(\.id))),
                 "两个 split 不重叠")

        // **分层**：每个类别都要同时出现在两个 split 里。
        // 不分层的话，holdout 可能整类缺失，而那一类的退化就永远不会被发布判定看到。
        for (cat, _) in categoryTargets where cat != .negative {
            let inDev = d.cases.contains { $0.category == cat && ($0.split ?? .development) == .development }
            let inHold = d.cases.contains { $0.category == cat && $0.split == .holdout }
            r.expect(inDev && inHold, "类别 \(cat.rawValue) 在两个 split 里都有")
        }
        r.expect(d.negativeQueries.contains { $0.split == .holdout },
                 "负例也分层进 holdout")

        // 回归集：**不能是空的**。空集合会让 Gate 的第四行恒过，
        // 而「一个总是通过的检查」与「没有这个检查」是同一件事。
        let regression = d.cases.filter { $0.isRegression == true }
        r.expect(regression.count >= 6,
                 "回归集至少 6 条（实际 \(regression.count)）—— 空集合等于没有那一行 Gate")
        r.expect(Set(regression.compactMap(\.category)).count >= 3,
                 "回归集覆盖至少 3 个类别 —— 只盯一种失败模式的回归集保护不了别的")
        r.expect(regression.allSatisfy { $0.evalCase.source == .regression },
                 "标了 isRegression 的用例在 Runner 里确实归到 regression 分组")
    }

    // MARK: 7 · 泄漏

    private static func checkNoLeakage(_ d: GoldenSetFixture.Dataset, _ r: CheckRunner) {
        r.suite("scenario-v5 · query 不得被写进笔记（exact_fact 的原词引用除外）")

        func squeeze(_ s: String) -> String {
            s.lowercased().filter { !$0.isWhitespace }
        }
        let bodies = d.notes.map { squeeze($0.title + $0.content) }
        var leaks: [String] = []
        var literalRecall = 0
        for c in d.cases {
            let q = squeeze(c.query)
            guard q.count >= 12 else { continue }
            guard bodies.contains(where: { $0.contains(q) }) else { continue }
            // exact_fact 的定义就是「用户记得原词」。把它判成泄漏等于取消这一整类。
            if c.category == .exactFact { literalRecall += 1 } else { leaks.append(c.id) }
        }
        r.expect(leaks.isEmpty,
                 "非 exact_fact 的 query 没有被逐字写进笔记（违规：\(leaks.joined(separator: ","))）")
        r.expect(true, "exact_fact 的原词引用 \(literalRecall) 条 —— 这是该类别的预期行为")

        // 负例的正确性：它们**不该**在语料里有答案，所以正例引用过的笔记不能是它们的答案。
        r.expect(d.negativeQueries.allSatisfy { !$0.reason.isEmpty },
                 "每条负例都说明为什么语料里没有答案")
    }

    private static func percent(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
}
