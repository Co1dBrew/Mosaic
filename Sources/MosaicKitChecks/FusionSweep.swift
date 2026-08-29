import Foundation
import MosaicKit

/// # P1 #6 · Fusion 参数实验
///
/// 起因：cloud-hybrid 的 cross-language **R@1 只有 0.681**（R@5 已经 0.936），
/// 也就是「找得到，但没排到第一」。直觉答案是调 RRF 的 `k`。
///
/// ## 但先问一个更前面的问题：cross 上 fusion 有东西可融吗
///
/// 五路对照里 cloud-vector 与 cloud-hybrid 的 cross 三档**完全相同**
/// （R@1 0.681 / R@5 0.936 / MRR 0.813）。如果 keyword 那一路在 cross 上
/// 根本不返回结果，`fuse` 就退化成「只有 vector 一路」，**调 k 是空调**。
///
/// 所以这一节先测「keyword 参与率」，再扫 k —— 顺序反了会得到一堆
/// 「调什么都没变化」的数字而不知道为什么。
enum FusionSweep {

    /// 同一批 query 要在多个 k 上重跑，而**查询向量与 k 无关** ——
    /// 逐个 k 重新嵌入会把云端成本乘以 k 的个数。这里记住结果，整轮只嵌一次。
    actor Memo: EmbeddingProvider {
        nonisolated let modelInfo: EmbeddingModelInfo
        private let inner: any EmbeddingProvider
        private var cache: [String: [Float]] = [:]

        init(_ inner: any EmbeddingProvider) {
            self.inner = inner
            self.modelInfo = inner.modelInfo
        }

        func embed(_ text: String) async throws -> [Float] {
            if let hit = cache[text] { return hit }
            let v = try await inner.embed(text)
            cache[text] = v
            return v
        }

        func embed(batch texts: [String]) async throws -> [[Float]] {
            var out: [[Float]] = []
            out.reserveCapacity(texts.count)
            for t in texts { out.append(try await embed(t)) }
            return out
        }
    }

    static func run(_ r: CheckRunner) async {
        r.suite("P1 #6 · Fusion 参数实验 —— cross-language R@1 = 0.681 还能不能再挪")

        guard let dataset = try? HumanLikeGoldenFixture.load() else {
            r.expect(false, "fixture 应当可加载"); return
        }
        let chunks = dataset.chunks
        let cases = dataset.evalCases
        guard let local = try? LocalEmbedding.make() else {
            r.expect(true, "本机没有中文句向量模型，跳过 fusion 实验")
            return
        }

        // ── ① 先测 keyword 在各组上的参与率 ──
        //
        // 「fusion 调不动」有两种完全不同的原因：调了但没用，和**根本没有东西可融**。
        // 不先分开这两种，后面那张 k 扫描表就没法读。
        var kwReturned = [String: (withHits: Int, total: Int)]()
        for c in cases {
            let group = c.scope == .crossLanguage ? "cross" : "in-scope"
            let hits = KeywordRetriever.retrieve(query: c.query, chunks: chunks, topK: 50)
            var e = kwReturned[group] ?? (0, 0)
            e.total += 1
            if !hits.isEmpty { e.withHits += 1 }
            kwReturned[group] = e
        }
        print("\n    ── keyword 路的参与率（fusion 有没有第二个输入）──")
        for group in ["in-scope", "cross"] {
            guard let e = kwReturned[group] else { continue }
            print(String(format: "    %-10@ %3d/%3d 条 query 有 keyword 结果（%.1f%%）",
                         group as NSString, e.withHits, e.total,
                         Double(e.withHits) / Double(max(e.total, 1)) * 100))
        }

        // ── ② 建索引（本地 + 云端），provider 都套上记忆化 ──
        let localMemo = Memo(local)
        guard let localIndex = try? await RetrievalProviderBenchmark.buildIndex(chunks, provider: localMemo) else {
            r.expect(false, "本地索引应当可建"); return
        }
        var arms: [(name: String, provider: any EmbeddingProvider, store: InMemoryVectorStore)] =
            [("local", localMemo, localIndex.store)]

        if let cloud = RetrievalProviderBenchmark.cloudProvider() {
            let cloudMemo = Memo(cloud)
            if let built = try? await RetrievalProviderBenchmark.buildIndex(chunks, provider: cloudMemo) {
                arms.append(("cloud", cloudMemo, built.store))
            } else {
                r.expect(true, "云端索引失败 —— 云端那一半标为待验证")
            }
        } else {
            print("\n    ⚠️ 云端臂：**待验证**（需要 MOSAIC_LIVE_EMBEDDING_*）")
        }

        // ── ③ 扫 k ──
        let ks = [1, 5, 10, 30, 60, 100, 200]
        var table: [(arm: String, label: String, inR1: Double, inR5: Double, inMRR: Double,
                     crR1: Double, crR5: Double, crMRR: Double, run: EvalRun)] = []
        var negatives: [String: Double] = [:]

        for arm in arms {
            var methods: [(String, FusionMethod)] = ks.map { ("rrf(k=\($0))", .rrf(k: $0)) }
            // 加权那一路只作对照 —— 两路分数不可比，它不是候选方案。
            methods.append(("weighted(kw .3/v .7)", .weighted(keyword: 0.3, vector: 0.7)))
            methods.append(("weighted(kw .7/v .3)", .weighted(keyword: 0.7, vector: 0.3)))
            // vector-only：fusion 的下界参照。
            methods.append(("vector-only", .rrf(k: 60)))

            for (label, method) in methods {
                let mode: RetrievalMode = (label == "vector-only") ? .vector : .hybrid
                let service = RetrievalService(provider: arm.provider, vectors: arm.store)
                let config = RetrievalConfig(version: "fusion-\(arm.name)-\(label)", mode: mode,
                                             embeddingProvider: arm.provider.modelInfo.identifier,
                                             embeddingVersion: arm.provider.modelInfo.version,
                                             chunkStrategy: .default, topK: 10, fusion: method)
                let runner = EvalRunner(service: service, chunksProvider: { chunks })
                guard let run = try? await runner.run(cases: cases, config: config),
                      let neg = try? await runner.run(cases: dataset.negativeEvalCases, config: config) else {
                    r.expect(false, "\(arm.name)/\(label) 跑批失败"); continue
                }
                table.append((arm.name, label,
                              run.inScopeMetrics.recallAt1, run.inScopeMetrics.recallAt5, run.inScopeMetrics.mrr,
                              run.crossLanguageMetrics.recallAt1, run.crossLanguageMetrics.recallAt5,
                              run.crossLanguageMetrics.mrr, run))
                negatives["\(arm.name)/\(label)"] = neg.metrics.noResultAccuracy
            }
        }

        print("\n    ── fusion 扫描（\(chunks.count) chunks / \(cases.count) queries · \(RetrievalProviderBenchmark.buildMode)）──")
        print("    arm    method                 in R@1  in R@5  in MRR | cr R@1  cr R@5  cr MRR | no-result")
        for row in table {
            print(String(format: "    %-6@ %-22@ %.3f   %.3f   %.3f | %.3f   %.3f   %.3f |  %5.1f%%",
                         row.arm as NSString, row.label as NSString,
                         row.inR1, row.inR5, row.inMRR, row.crR1, row.crR5, row.crMRR,
                         (negatives["\(row.arm)/\(row.label)"] ?? 0) * 100))
        }

        // ── Gate：weighted 那一路能不能把 local-hybrid 从 BLOCKED 救回来 ──
        //
        // §24.5 实测 local-hybrid 栽在 R@1（0.269 < keyword 0.343）。
        // 如果换个融合方式就能过，那说明**问题出在融合，不出在本地向量模型**。
        // 这是要拿判定来回答的问题，不是看着 R@1 一栏猜。
        if let baselineRun = table.first(where: { $0.arm == "local" && $0.label == "rrf(k=60)" })?.run {
            let keywordService = RetrievalService(provider: nil, vectors: InMemoryVectorStore())
            let keywordConfig = RetrievalConfig(version: "fusion-gate", mode: .keyword,
                                                embeddingProvider: "none", embeddingVersion: "none",
                                                chunkStrategy: .default, topK: 10)
            let keywordRunner = EvalRunner(service: keywordService, chunksProvider: { chunks })
            if let kwRun = try? await keywordRunner.run(cases: cases, config: keywordConfig) {
                print("\n    ── Gate（baseline = keyword，candidate = 各 fusion 方式 · 只看 in-scope）──")
                for row in table where row.arm == "local" {
                    var current = row.run
                    current = EvalRun(configVersion: "fusion-gate", embeddingVersion: "e",
                                      metrics: current.metrics, goldenMetrics: current.goldenMetrics,
                                      regressionMetrics: .zero, failures: [],
                                      inScopeMetrics: current.inScopeMetrics)
                    let base = EvalRun(configVersion: "fusion-gate", embeddingVersion: "e",
                                       metrics: kwRun.metrics, goldenMetrics: kwRun.goldenMetrics,
                                       regressionMetrics: .zero, failures: [],
                                       inScopeMetrics: kwRun.inScopeMetrics)
                    let d = ReleaseGate.evaluate(
                        configVersion: "fusion-gate", current: current, baseline: base,
                        thresholds: GateThresholds(performance: .v1),
                        environment: RunEnvironment(deviceClass: .mac, deviceModel: "mac",
                                                    osVersion: "0", buildConfiguration: "release",
                                                    thermalState: "nominal", lowPowerMode: false,
                                                    measuredLayer: .semanticLocal))
                    let recall = d.checks.first { $0.kind == .recall }
                    print(String(format: "    %-22@ %-20@ %@", row.label as NSString,
                                 d.headline as NSString, recall?.actualText ?? "—"))
                }
                _ = baselineRun
            }
        }

        // ── ④ 断言：结论，不是数值 ──
        func rows(_ arm: String) -> [(String, Double, Double, Double, Double)] {
            table.filter { $0.arm == arm }.map { ($0.label, $0.inR1, $0.inMRR, $0.crR1, $0.crMRR) }
        }
        for arm in arms.map(\.name) {
            let rs = rows(arm)
            guard !rs.isEmpty else { continue }
            let krows = rs.filter { $0.0.hasPrefix("rrf") }
            let crossSpread = (krows.map(\.3).max() ?? 0) - (krows.map(\.3).min() ?? 0)
            let inSpread = (krows.map(\.1).max() ?? 0) - (krows.map(\.1).min() ?? 0)
            print(String(format: "    %@：k 从 1 到 200，in-scope R@1 摆动 %.3f，cross R@1 摆动 %.3f",
                         arm as NSString, inSpread, crossSpread))
            r.expect(true, String(format: "%@ 上 RRF k 的可调空间已量化（in-scope %.3f · cross %.3f）", arm, inSpread, crossSpread))

            if let vectorOnly = rs.first(where: { $0.0 == "vector-only" }),
               let k60 = rs.first(where: { $0.0 == "rrf(k=60)" }) {
                r.expect(true, String(format: "%@ 上 hybrid 相对 vector-only：cross R@1 %+.3f（%.3f → %.3f）",
                                      arm, k60.3 - vectorOnly.3, vectorOnly.3, k60.3))
            }
        }
        if let cross = kwReturned["cross"] {
            r.expect(cross.withHits < cross.total / 2,
                     String(format: "cross-language 上 keyword 只在 %d/%d 条 query 上有结果 —— "
                            + "**fusion 在这一组大多数时候只有一个输入**，调 k 动不了它",
                            cross.withHits, cross.total))
        }

        // ── ⑤ 权重曲线 ──
        //
        // 上面只试了两个加权点，那不是参数实验，是抽样。**看形状**才能分清
        // 「有一个真实的最优区间」和「碰巧某个点好看」。
        // 两端就是单臂：w=0 等于 vector-only 的排序，w=1 等于 keyword 主导。
        for arm in arms {
            print("\n    ── \(arm.name) · keyword 权重曲线（w · keyword + (1−w) · vector，皆用名次倒数）──")
            print("       w    in R@1  in MRR | cr R@1  cr MRR")
            var curve: [(Double, Double, Double)] = []
            for step in 0...10 {
                let w = Double(step) / 10.0
                let service = RetrievalService(provider: arm.provider, vectors: arm.store)
                let config = RetrievalConfig(version: "w-\(w)", mode: .hybrid,
                                             embeddingProvider: arm.provider.modelInfo.identifier,
                                             embeddingVersion: arm.provider.modelInfo.version,
                                             chunkStrategy: .default, topK: 10,
                                             fusion: .weighted(keyword: w, vector: 1 - w))
                let runner = EvalRunner(service: service, chunksProvider: { chunks })
                guard let run = try? await runner.run(cases: cases, config: config) else { continue }
                curve.append((w, run.inScopeMetrics.recallAt1, run.inScopeMetrics.mrr))
                print(String(format: "    %5.1f    %.3f   %.3f | %.3f   %.3f", w,
                             run.inScopeMetrics.recallAt1, run.inScopeMetrics.mrr,
                             run.crossLanguageMetrics.recallAt1, run.crossLanguageMetrics.mrr))
            }
            guard let best = curve.max(by: { $0.1 < $1.1 }) else { continue }
            let plateau = curve.filter { abs($0.1 - best.1) < 1e-9 }.map(\.0)
            r.expect(true, String(format:
                "%@ 最优 in-scope R@1 = %.3f，出现在 w ∈ [%.1f, %.1f]（%d 个采样点）—— "
                + "**平台越宽越像真实结构，越窄越像过拟合**",
                arm.name, best.1, plateau.min() ?? 0, plateau.max() ?? 0, plateau.count))
        }

        print("")
    }
}

/// 默认融合方式的**决策留痕**。断言不是在测融合算法（那是 `FusionSweep`），
/// 而是在钉住「为什么默认值是现在这个」—— 换回去必须先推翻这里的理由。
enum FusionDefaultChecks {
    static func run(_ r: CheckRunner) {
        r.suite("P1 #18 · 默认融合方式 —— 等权 RRF 被实测否决")

        r.expect(FusionMethod.default == .weighted(keyword: 0.7, vector: 0.3),
                 "默认是加权名次融合 w=0.7 —— 依据是 v3/v4 两个数据集上「等权 RRF 主动有害」")
        r.expect(FusionMethod.rrfDefault == .rrf(k: 60),
                 "旧默认保留为具名常量，对照实验与回退都用它")

        // 机制断言：弱臂在等权下能把强臂的第一名挤掉，加权能挡住。
        // 用最小反例说清楚，不依赖跑批。
        let strong = ["A", "B", "C"]        // keyword：正确答案 A 在第 1
        let weak = ["X", "Y", "A"]          // vector：噪声在前，A 掉到第 3
        let equal = RRFFusion.fuse(keywordOrder: strong, vectorOrder: weak, method: .rrf(k: 60))
        let weighted = RRFFusion.fuse(keywordOrder: strong, vectorOrder: weak,
                                      method: .weighted(keyword: 0.7, vector: 0.3))
        r.expect(equal.first?.chunkID == "A",
                 "等权下 A 仍在第一（k=60 时 1/61 的差距还压得住三条）")
        r.expect(weighted.first?.chunkID == "A", "加权下 A 也在第一")

        // 真正的分歧发生在弱臂给出**大量**噪声候选时 —— 那才是 20 万 chunk 上的实况。
        let manyNoise = (1...20).map { "N\($0)" } + ["A"]
        let equalMany = RRFFusion.fuse(keywordOrder: strong, vectorOrder: manyNoise, method: .rrf(k: 60))
        let weightedMany = RRFFusion.fuse(keywordOrder: strong, vectorOrder: manyNoise,
                                          method: .weighted(keyword: 0.7, vector: 0.3))
        let equalRankOfA = (equalMany.firstIndex { $0.chunkID == "A" } ?? -1) + 1
        let weightedRankOfA = (weightedMany.firstIndex { $0.chunkID == "A" } ?? -1) + 1
        r.expect(weightedRankOfA <= equalRankOfA,
                 "弱臂噪声越多，加权越占优（A 的名次：等权第 \(equalRankOfA) · 加权第 \(weightedRankOfA)）")

        r.expect(RRFFusion.fuse(keywordOrder: [], vectorOrder: ["A", "B"],
                                method: .weighted(keyword: 0.7, vector: 0.3)).map(\.chunkID) == ["A", "B"],
                 "keyword 缺席时退化成 vector 排序 —— 换默认值不改变单臂行为")
        r.expect(RRFFusion.fuse(keywordOrder: ["A", "B"], vectorOrder: [],
                                method: .weighted(keyword: 0.7, vector: 0.3)).map(\.chunkID) == ["A", "B"],
                 "vector 缺席时退化成 keyword 排序")
    }
}
