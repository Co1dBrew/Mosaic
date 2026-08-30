import Foundation
import MosaicKit

/// # `scenario-v5` 上的基线评测（Phase 4）
///
/// ## 三个臂，一条基线
///
/// | arm | 是什么 | 在判定里的角色 |
/// |---|---|---|
/// | `keyword` | **当前生产 baseline**：纯词法快通道 | 比较的分母 |
/// | `local-hybrid` | 候选：keyword + 本机句向量，weighted 0.7/0.3 | 被判定的那个 |
/// | `cloud-hybrid` | 候选：keyword + 云端 bge-m3 | 缺凭据时**判 NOT RUN**，不算 PASS |
///
/// **baseline 必须是候选真正准备替代的那一套。** 选一个「容易赢」的软基线
/// （比如随机排序）会让任何改动都显得成功 —— 那样的比较没有信息量。
/// 生产现在跑的就是隐式 hybrid，而 hybrid 的下界是 keyword 单路，
/// 所以 keyword 是那个诚实的分母。
///
/// ## 这个 suite 断言什么、不断言什么
///
/// **断言**：跑批能完成、分组口径正确、判定链路闭合、逐用例结果齐全（否则算不了
/// 置信区间）、holdout 与 development 分开跑。
///
/// **不断言**「候选必须 PASS」。质量数字是**测量结果**，把它写成断言就等于
/// 把「这一版必须过」编译进代码 —— 之后任何真实的退化都会被当成测试坏了。
/// 判定结果打印出来，由人读。
enum ScenarioBaselineEvaluation {

    static func run(_ r: CheckRunner) async {
        r.suite("scenario-v5 · 基线评测（keyword baseline vs local-hybrid candidate）")

        guard let dataset = try? HumanLikeGoldenFixture.load() else {
            r.expect(false, "fixture 应当可加载"); return
        }
        guard let provider = try? LocalEmbedding.make() else {
            // 本机没有中文句向量模型（Mac 上常见）时，**不退回 mock**：
            // 伪向量会让 Recall 看起来正常但毫无产品含义。
            r.expect(true, "本机没有句向量模型，跳过基线评测；结构检查仍有效")
            print("\n    ⚠️ 本机无 NLEmbedding，基线评测 NOT RUN。"
                  + "结论「待验证」，不得当作通过。\n")
            return
        }

        let chunks = dataset.chunks
        let store = InMemoryVectorStore()
        for chunk in chunks {
            guard let vector = try? await provider.embed(chunk.text) else {
                r.expect(false, "\(chunk.id) 应可嵌入"); return
            }
            await store.upsert(EmbeddingRecord(ref: chunk.ref, chunkID: chunk.id,
                                               chunkIndex: chunk.indexInBlock,
                                               contentHash: chunk.contentHash,
                                               embeddingVersion: provider.modelInfo.version,
                                               chunkStrategy: chunk.strategy,
                                               dimension: provider.modelInfo.dimension,
                                               vector: vector))
        }

        func config(_ mode: RetrievalMode, _ name: String) -> RetrievalConfig {
            RetrievalConfig(version: "scenario-v5-\(name)", mode: mode,
                            embeddingProvider: provider.modelInfo.identifier,
                            embeddingVersion: provider.modelInfo.version,
                            chunkStrategy: .default, topK: 10)
        }

        let runner = EvalRunner(service: RetrievalService(provider: provider, vectors: store),
                                chunksProvider: { chunks })

        var runs: [String: [GoldenSetFixture.Split: EvalRun]] = [:]
        for (name, mode) in [("keyword", RetrievalMode.keyword), ("local-hybrid", .hybrid)] {
            for split in GoldenSetFixture.Split.allCases {
                let cases = dataset.evalCases(split: split)
                do {
                    let run = try await runner.run(cases: cases, config: config(mode, name))
                    runs[name, default: [:]][split] = run
                    r.expect(run.outcomes.count == cases.count,
                             "\(name)/\(split.rawValue) 逐用例结果齐全 —— 缺了就算不了置信区间")
                    r.expect(run.inScopeMetrics.caseCount > 0,
                             "\(name)/\(split.rawValue) in-scope 分组非空")
                } catch {
                    r.expect(false, "\(name)/\(split.rawValue) 跑批失败：\(error)")
                    return
                }
            }
        }

        // 两个 split 的用例集合不重叠 —— 这是「holdout 只用于发布判定」的前提。
        let devIDs = Set(dataset.evalCases(split: .development).map(\.id))
        let holdIDs = Set(dataset.evalCases(split: .holdout).map(\.id))
        r.expect(devIDs.isDisjoint(with: holdIDs), "development 与 holdout 用例不重叠")

        printTable(runs, dataset: dataset)
        printRegressionRoster(runs["local-hybrid"], dataset: dataset, r: r)
        await printSampleFailures(dataset: dataset, provider: provider, store: store,
                                  chunks: chunks, config: config(.hybrid, "local-hybrid"), r: r)
        printCategoryBreakdown(runs["local-hybrid"]?[.development], baseline: runs["keyword"]?[.development],
                               dataset: dataset)
        judge(runs, r: r)
        reportCloudArm(r)
    }

    // MARK: 表格

    private static func printTable(_ runs: [String: [GoldenSetFixture.Split: EvalRun]],
                                   dataset: GoldenSetFixture.Dataset) {
        print("""

            ── scenario-v5 基线评测（Mac · debug · 本机 NLEmbedding zh-Hans）──
            语料 \(dataset.notes.count) 篇 · query \(dataset.cases.count + dataset.negativeQueries.count) 条
            ⚠️ 数据是 agent 编写的场景化用例（provenance=agent_authored_realistic），
               不是真实用户标注。数字只用于**两套配置之间的比较**。
            """)
        print("    arm            split        n    R@1    R@3    R@5    MRR    no-result   P50      P95")
        for name in ["keyword", "local-hybrid"] {
            for split in GoldenSetFixture.Split.allCases {
                guard let run = runs[name]?[split] else { continue }
                let m = run.inScopeMetrics
                let neg = run.metrics
                print(String(format: "    %-14s %-11s %3d  %.3f  %.3f  %.3f  %.3f     %5.1f%%  %6.2f  %7.2f",
                             (name as NSString).utf8String!, (split.rawValue as NSString).utf8String!,
                             m.caseCount, m.recallAt1, m.recallAt3, m.recallAt5, m.mrr,
                             neg.noResultAccuracy * 100, m.p50Ms, m.p95Ms))
            }
        }
        print("")
    }

    /// 按类别切片。**这是 v5 相对 v4 最大的实用差别**：
    /// 「总体低了 0.03」说明不了该改什么，「lexical_trap 掉了 0.20 而其它类没动」说明得很清楚。
    private static func printCategoryBreakdown(_ candidate: EvalRun?, baseline: EvalRun?,
                                               dataset: GoldenSetFixture.Dataset) {
        guard let candidate, let baseline else { return }
        let categoryOf = Dictionary(uniqueKeysWithValues:
            dataset.cases.compactMap { c in c.category.map { (c.id, $0) } })
        func byCategory(_ run: EvalRun) -> [GoldenSetFixture.Category: (hit: Int, n: Int)] {
            var out: [GoldenSetFixture.Category: (hit: Int, n: Int)] = [:]
            // 分母与 Recall@1 一致：多答案的用例在 Top-1 里不可满足，
            // 算进来会让 `ambiguous` 恒为 0.000，看起来像能力缺失，其实是口径问题。
            for o in run.outcomes where o.participates(in: .recallAt1) && o.scope == .inScope {
                guard let cat = categoryOf[o.caseID] else { continue }
                var entry = out[cat] ?? (0, 0)
                entry.hit += o.hitAt1 ? 1 : 0
                entry.n += 1
                out[cat] = entry
            }
            return out
        }
        let cand = byCategory(candidate), base = byCategory(baseline)
        print("    ── development · R@1 按类别（candidate local-hybrid vs baseline keyword）──")
        print("    category              n   baseline  candidate   delta")
        for cat in GoldenSetFixture.Category.allCases {
            guard let c = cand[cat], let b = base[cat], c.n > 0 else { continue }
            let cr = Double(c.hit) / Double(c.n), br = Double(b.hit) / Double(b.n)
            print(String(format: "    %-20s %3d     %.3f      %.3f   %+.3f",
                         (cat.rawValue as NSString).utf8String!, c.n, br, cr, cr - br))
        }
        print("")
    }

    /// 回归集逐条点名。
    ///
    /// **回归集是一个棘轮**：它固定「现在有的、不许丢的」行为。
    /// 把一条**当前就失败**的用例放进去，Gate 会因为一个不是回归的原因永久变红，
    /// 而一个永远红的 Gate 会被忽略 —— 那正是「一个总是被跳过的 Gate 等于
    /// 没有 Gate」。当前失败的用例属于 backlog，不属于回归集。
    ///
    /// 所以这里逐条打印通过情况：名单要按它来维护。
    private static func printRegressionRoster(_ runs: [GoldenSetFixture.Split: EvalRun]?,
                                              dataset: GoldenSetFixture.Dataset,
                                              r: CheckRunner) {
        guard let runs else { return }
        var outcomes: [String: EvalCaseOutcome] = [:]
        for (_, run) in runs {
            for o in run.outcomes { outcomes[o.caseID] = o }
        }
        let regression = dataset.cases.filter { $0.isRegression == true }
        guard !regression.isEmpty else { return }
        print("    ── 回归集点名（local-hybrid · dev + holdout 合并）──")
        var passing = 0
        for c in regression.sorted(by: { $0.id < $1.id }) {
            guard let o = outcomes[c.id] else { continue }
            let mark = o.hitAt5 ? "✅" : "❌"
            if o.hitAt5 { passing += 1 }
            print("      \(mark) \(c.id)  \(c.category?.rawValue ?? "?")  \(c.query)")
        }
        print("      通过 \(passing)/\(regression.count)\n")
        // 断言的是**名单的性质**，不是通过率：回归集里出现当前失败的用例，
        // 说明名单该改，而不是说明系统坏了。
        r.expect(passing == regression.count,
                 "回归集里每一条都当前通过（实际 \(passing)/\(regression.count)）—— "
                 + "不通过的属于 backlog，不属于棘轮")
    }

    /// 逐类抽一条失败用例，把**实际返回的前三条**打出来。
    ///
    /// 写它的直接原因：第一次跑出 `near_duplicate` / `noisy_query` /
    /// `contextual_recall` 三类 R@1 全是 0.000，而 `exact_fact` 是 0.905。
    /// 「整类全 0」既可能是数据集真的难，也可能是标注错了 —— 这两种情况的
    /// 补救动作完全相反，不看具体返回就分不清。看过之后确认是前者。
    private static func printSampleFailures(dataset: GoldenSetFixture.Dataset,
                                            provider: any EmbeddingProvider,
                                            store: InMemoryVectorStore,
                                            chunks: [NoteChunk],
                                            config: RetrievalConfig,
                                            r: CheckRunner) async {
        let service = RetrievalService(provider: provider, vectors: store)
        let titles = Dictionary(uniqueKeysWithValues: dataset.notes.map { ($0.id, $0.title) })
        print("    ── 抽样失败（local-hybrid，每类一条）──")
        var checked = 0
        for category in GoldenSetFixture.Category.allCases where category != .negative {
            guard let sample = dataset.cases.first(where: {
                $0.category == category && $0.scope == .inScope && $0.difficulty == .hard
            }) ?? dataset.cases.first(where: { $0.category == category && $0.scope == .inScope })
            else { continue }
            let outcome = await service.retrieve(query: sample.query, chunks: chunks, config: config)
            var seen = Set<String>()
            let top = outcome.results.compactMap { result -> String? in
                guard seen.insert(result.ref.noteID).inserted else { return nil }
                return "\(result.ref.noteID)（\(titles[result.ref.noteID] ?? "?")）"
            }.prefix(3)
            let want = sample.expectedNoteIDs.map { "\($0)（\(titles[$0] ?? "?")）" }.joined(separator: " / ")
            print("      \(category.rawValue) · \(sample.id)")
            print("        query    \(sample.query)")
            print("        期望     \(want)")
            print("        实际前三 \(top.joined(separator: " → "))")
            // 抽样本身也是断言：期望笔记必须真的在语料里能被检索到
            // （只要放宽到全库扫描）。查不到说明的是标注错了，不是模型差。
            let reachable = chunks.contains { sample.expectedNoteIDs.contains($0.ref.noteID) }
            r.expect(reachable, "\(sample.id) 的期望笔记在语料里（否则是标注错误，不是检索失败）")
            checked += 1
        }
        print("")
        r.expect(checked >= 6, "抽样覆盖了至少 6 个类别（实际 \(checked)）")
    }

    // MARK: 判定

    private static func judge(_ runs: [String: [GoldenSetFixture.Split: EvalRun]], r: CheckRunner) {
        guard let baselineDev = runs["keyword"]?[.development],
              let candidateDev = runs["local-hybrid"]?[.development],
              let baselineHold = runs["keyword"]?[.holdout],
              let candidateHold = runs["local-hybrid"]?[.holdout] else { return }

        // **质量判定与延迟判定分开。**
        //
        // `perf-v2` 的环境闸门（release + 真机）是给延迟结论设的。质量结论不受
        // 构建配置影响 —— v4 那一轮真机与 Mac 的质量数字逐位相同，差别只在延迟。
        // 用延迟的环境要求去卡质量比较，结果是每次都判 STALE，于是没有人再看它。
        //
        // 所以这里用 `perf-none`：**只判质量，连延迟那一行都不出**。
        // 延迟仍然只在真机 release 的 `MosaicBench` 上有结论。
        var thresholds = GateThresholds.v1
        thresholds.performance = .qualityOnly
        let env = RunEnvironment.capture(layer: .firstResult)

        for (label, baseline, candidate) in [("development", baselineDev, candidateDev),
                                             ("holdout", baselineHold, candidateHold)] {
            let decision = ReleaseGate.evaluate(configVersion: candidate.configVersion,
                                                current: candidate, baseline: baseline,
                                                thresholds: thresholds, environment: env)
            print("    ── Gate（\(thresholds.version) · \(label)）→ \(decision.headline) ──")
            for check in decision.checks {
                print("      \(check.passed ? "✅" : "❌") \(check.kind.label): \(check.actualText)")
                print("         要求 \(check.conditionText)")
                if let detail = check.detail { print("         · \(detail)") }
            }
            if let stale = decision.staleReason { print("      · \(stale)") }
            print("")

            // 断言的是**判定链路**，不是判定结果。
            r.expect(!decision.checks.isEmpty || decision.status == GateDecision.Status.stale,
                     "\(label) 判定给出了完整的检查项或明确的 STALE 原因")
            r.expect(decision.checks.contains { $0.kind == GateCheck.Kind.absoluteFloor },
                     "\(label) 判定包含绝对下限这一行（gate-v1 的三件套之一）")
            r.expect(decision.checks.contains { $0.kind == GateCheck.Kind.recall },
                     "\(label) 判定包含 Recall 主指标")
        }

        // 统计置信本身要有断言：同一份数据自己和自己比，不能报出「显著退化」。
        if let ci = PairedBootstrap.deltaInterval(current: candidateDev.outcomes,
                                                 baseline: candidateDev.outcomes,
                                                 metric: .recallAt1) {
            r.expect(abs(ci.delta) < 1e-9, "自己与自己比较的 delta 为 0")
            r.expect(!ci.isMeaningfulRegression && !ci.isMeaningfulImprovement,
                     "自己与自己比较既不算退化也不算提升（\(ci.summary)）")
        } else {
            r.expect(false, "development 的配对样本量应当足够算置信区间")
        }
    }

    // MARK: 云端臂

    /// 云端臂需要四个环境变量。**缺凭据时判 NOT RUN，不判 PASS。**
    /// 一个「因为没跑所以没失败」的臂，写成绿色就是在骗自己。
    private static func reportCloudArm(_ r: CheckRunner) {
        let env = ProcessInfo.processInfo.environment
        let keys = ["MOSAIC_LIVE_EMBEDDING_BASE", "MOSAIC_LIVE_EMBEDDING_KEY",
                    "MOSAIC_LIVE_EMBEDDING_MODEL", "MOSAIC_LIVE_EMBEDDING_DIM"]
        let missing = keys.filter { (env[$0] ?? "").isEmpty }
        if missing.isEmpty {
            print("    cloud-hybrid：凭据齐备。用 `RetrievalProviderBenchmark` 跑云端臂。\n")
            r.expect(true, "云端臂凭据齐备")
        } else {
            print("""
                    cloud-hybrid：**NOT RUN — MISSING CREDENTIALS**
                      缺少 \(missing.joined(separator: ", "))
                      结论是「待验证」，不是「通过」。凭据在 ~/.mosaic-cloud.env，source 后重跑。

                """)
            r.expect(true, "云端臂 NOT RUN 已如实记录（缺 \(missing.count) 个环境变量）")
        }
    }
}
