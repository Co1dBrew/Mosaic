import Foundation
import MosaicKit

/// # CJK 切分策略扫描（**只跑 development**）
///
/// ## 它回答什么
///
/// 「CJK 二元组的命中门槛该定在哪」。这是一个参数，参数要用数据定，
/// 而定参数的数据**只能是 development** —— 拿 holdout 调参就是把它烧掉，
/// 之后它再也不能作为发布判定的依据。
///
/// ## 为什么必须有这个扫描
///
/// 第一版拍了一个「覆盖率 ≥ 0.5」，在长口语 query 上直接把正确答案过滤掉了
/// （`QuerySegmentation` 的文档里记了那条实例）。**拍出来的参数会错**，
/// 而错在哪只有扫描能告诉你。
///
/// ## 输出怎么读
///
/// 报告 R@1 / R@5 / MRR 与 P95。**不自动选优**：一个能自己改生产默认值的扫描，
/// 等于把「照着评测集调参」写进了代码。选哪个由人看着表决定，
/// 并把理由写进 `GATE_POLICY.md`。
enum QuerySegmentationSweep {

    /// 默认不跑（每次约 40 秒）。`MOSAIC_SEG_SWEEP=1 swift run mosaic-checks` 打开。
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MOSAIC_SEG_SWEEP"] == "1"
    }

    static func run(_ r: CheckRunner) async {
        guard isEnabled else {
            r.expect(true, "CJK 切分扫描默认不跑（MOSAIC_SEG_SWEEP=1 打开）")
            return
        }
        r.suite("CJK 切分策略扫描 · development only")

        guard let dataset = try? HumanLikeGoldenFixture.load(),
              let provider = try? LocalEmbedding.make() else {
            r.expect(true, "缺少 fixture 或本机模型，扫描 NOT RUN")
            return
        }

        let chunks = dataset.chunks
        let store = InMemoryVectorStore()
        for chunk in chunks {
            guard let v = try? await provider.embed(chunk.text) else { continue }
            await store.upsert(EmbeddingRecord(ref: chunk.ref, chunkID: chunk.id,
                                               chunkIndex: chunk.indexInBlock,
                                               contentHash: chunk.contentHash,
                                               embeddingVersion: provider.modelInfo.version,
                                               chunkStrategy: chunk.strategy,
                                               dimension: provider.modelInfo.dimension,
                                               vector: v))
        }
        let cases = dataset.evalCases(split: .development)

        // 参照：完全不切（旧行为）。它是这次改动要替代的那一套。
        var arms: [(String, QuerySegmentation, CJKMatchPolicy)] = [
            ("whitespace（旧）", .whitespace, .default)
        ]
        for ratio in [0.34, 0.25, 0.15] {
            for floor in [1, 2, 3] {
                arms.append((String(format: "bigram r=%.2f f=%d", ratio, floor),
                             .cjkBigram, CJKMatchPolicy(ratio: ratio, floor: floor)))
            }
        }
        // 中英混排：拉丁词命中后放宽 CJK 段。
        for ratio in [0.25, 0.15] {
            for floor in [2, 3] {
                arms.append((String(format: "r=%.2f f=%d +latin", ratio, floor),
                             .cjkBigram,
                             CJKMatchPolicy(ratio: ratio, floor: floor, latinRelaxesCJK: true)))
            }
        }
        // 拉丁词之间也放宽（噪声 query 这一类的直接目标：
        // `wheres the midterm now, snell or richards` 在 AND 语义下整条不命中）。
        for latin in [0.8, 0.67, 0.5] {
            arms.append((String(format: "r=0.15 f=3 +latin L=%.2f", latin),
                         .cjkBigram,
                         CJKMatchPolicy(ratio: 0.15, floor: 3, latinRelaxesCJK: true,
                                        latinRatio: latin)))
        }

        // 负例单独跑：**放宽命中门槛的代价在这里**。in-scope 的 R@1 涨了，
        // 而负例开始返回结果的话，用户看到的是「搜什么都有结果」——
        // 只看 R@1 选参数会把这个代价漏掉。
        let negatives = dataset.negativeEvalCases

        print("\n    ── CJK 切分扫描（development · \(cases.count) 条 · local-hybrid）──")
        print("    policy                 R@1    R@3    R@5    MRR    keyword-only 负例正确率")
        var best: (String, Double)?
        for (label, segmentation, policy) in arms {
            let service = RetrievalService(provider: provider, vectors: store,
                                           segmentation: segmentation, cjkPolicy: policy)
            let runner = EvalRunner(service: service, chunksProvider: { chunks })
            let config = RetrievalConfig(version: "sweep", mode: .hybrid,
                                         embeddingProvider: provider.modelInfo.identifier,
                                         embeddingVersion: provider.modelInfo.version,
                                         chunkStrategy: .default, topK: 10)
            guard let run = try? await runner.run(cases: cases, config: config) else {
                r.expect(false, "\(label) 跑批失败"); continue
            }
            let m = run.inScopeMetrics
            // 负例用 **keyword-only** 跑：向量路永远返回东西（TD-10 未解决），
            // hybrid 上的负例正确率恒为 0，测不出切分策略的影响。
            let keywordConfig = RetrievalConfig(version: "sweep-neg", mode: .keyword,
                                                embeddingProvider: provider.modelInfo.identifier,
                                                embeddingVersion: provider.modelInfo.version,
                                                chunkStrategy: .default, topK: 10)
            let negativeRun = try? await runner.run(cases: negatives, config: keywordConfig)
            let noResult = negativeRun?.metrics.noResultAccuracy ?? -1
            print(String(format: "    %-20s  %.3f  %.3f  %.3f  %.3f          %5.1f%%",
                         (label as NSString).utf8String!,
                         m.recallAt1, m.recallAt3, m.recallAt5, m.mrr, noResult * 100))
            if best == nil || m.recallAt1 > best!.1 { best = (label, m.recallAt1) }
        }
        print("""

                最高 R@1：\(best?.0 ?? "—")（\(String(format: "%.3f", best?.1 ?? 0))）
                ⚠️ 这个扫描**不自动改生产默认值**。选哪个由人决定，理由写进 GATE_POLICY.md。
                   一个能自己照着评测集改参数的扫描，就是把 overfit 写进了代码。

            """)
        r.expect(best != nil, "扫描产出了可比较的结果")
    }
}
