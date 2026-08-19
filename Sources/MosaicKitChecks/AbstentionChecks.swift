import Foundation
import MosaicKit

/// TD-10 —— 弃答策略的判决逻辑与**校准**。
///
/// 校准的目标函数**不是准确率**：漏掉一条真答案比多显示几条无关结果伤得多。
/// 所以约束是「正例零损失」，在这个约束下最大化负例挡掉率。
///
/// 并且**必须报余量** —— 上一轮在 `bge-m3` 上找到的最优阈值 0.54 距离最近一条正例
/// 只有 0.001，那种点估计不可发布。只报最优值不报余量，等于把一个必然翻车的
/// 阈值包装成结论。
enum AbstentionChecks {

    // MARK: 1 · 判决逻辑

    static func checkJudge(_ r: CheckRunner) {
        r.suite("TD-10 · 弃答判决 —— 三态，不做加权")

        let disabled = AbstentionPolicy.neverAbstains
        r.expect(!disabled.isEnabled, "默认策略未启用 —— 未校准前不动产品行为")
        r.expect(AbstentionJudge.judge(
            AbstentionSignals(top1Similarity: 0.01, margin: 0, top1ToMeanRatio: 1,
                              hasKeywordHit: false, candidateCount: 5),
            policy: disabled) == .confident,
                 "策略关闭时任何信号都判 confident —— 与接入前行为逐位一致")

        let policy = AbstentionPolicy(version: "test", similarityFloor: 0.50,
                                      minMargin: 0.05, floorWithoutLexicalSupport: 0.60)

        r.expect(AbstentionJudge.judge(
            AbstentionSignals(top1Similarity: nil, margin: nil, top1ToMeanRatio: nil,
                              hasKeywordHit: false, candidateCount: 0),
            policy: policy) == .abstain,
                 "一条候选都没有 → abstain（这不是「不确定」，是真的没有）")

        r.expect(AbstentionJudge.judge(
            AbstentionSignals(top1Similarity: nil, margin: nil, top1ToMeanRatio: nil,
                              hasKeywordHit: true, candidateCount: 3),
            policy: policy) == .confident,
                 "纯词法命中不由语义信号判决 —— 字面命中本身就是证据")

        r.expect(AbstentionJudge.judge(
            AbstentionSignals(top1Similarity: 0.42, margin: 0.20, top1ToMeanRatio: 2,
                              hasKeywordHit: true, candidateCount: 5),
            policy: policy) == .abstain,
                 "低于绝对下限 → abstain，即使 margin 很大")

        r.expect(AbstentionJudge.judge(
            AbstentionSignals(top1Similarity: 0.55, margin: 0.01, top1ToMeanRatio: 1.02,
                              hasKeywordHit: true, candidateCount: 5),
            policy: policy) == .abstain,
                 "过了下限但 margin 太小 → abstain（topK 一片扁平 = 没有突出答案）")

        r.expect(AbstentionJudge.judge(
            AbstentionSignals(top1Similarity: 0.55, margin: 0.30, top1ToMeanRatio: 3,
                              hasKeywordHit: false, candidateCount: 5),
            policy: policy) == .abstain,
                 "无字面支持时门槛更严（0.60）—— 0.55 不够")

        r.expect(AbstentionJudge.judge(
            AbstentionSignals(top1Similarity: 0.90, margin: 0.30, top1ToMeanRatio: 3,
                              hasKeywordHit: true, candidateCount: 5),
            policy: policy) == .confident, "信号都好 → confident")

        r.expect(AbstentionJudge.judge(
            AbstentionSignals(top1Similarity: 0.90, margin: 0.06, top1ToMeanRatio: 3,
                              hasKeywordHit: true, candidateCount: 5),
            policy: policy) == .uncertain,
                 "margin 刚过线但在不确定带内 → uncertain（照常显示，只加一行说明）")

        r.expect(RetrievalConfidence.uncertain.showsResults,
                 "uncertain **显示结果** —— 它只改文案，不改可见性")
        r.expect(!RetrievalConfidence.abstain.showsResults, "只有 abstain 不显示结果")

        // 只有一条候选时不因为「算不出 margin」而弃答。
        r.expect(AbstentionJudge.judge(
            AbstentionSignals(top1Similarity: 0.90, margin: nil, top1ToMeanRatio: nil,
                              hasKeywordHit: true, candidateCount: 1),
            policy: policy) == .confident,
                 "只有一条候选时算不出 margin，不能因此惩罚它")
    }

    // MARK: 2 · 信号提取

    static func checkSignalExtraction(_ r: CheckRunner) {
        r.suite("TD-10 · 信号提取 —— keyword 独有命中不压低 margin")

        func result(_ id: String, sim: Float?, ranges: [MosaicKit.TextRange]) -> RetrievalResult {
            RetrievalResult(chunkID: id, ref: BlockRef(noteID: "n", blockID: id),
                            source: .text, text: "t", fusedRank: 1,
                            keywordRank: ranges.isEmpty ? nil : 1,
                            vectorRank: sim == nil ? nil : 1,
                            similarity: sim, keywordScore: nil, matchedRanges: ranges)
        }
        let outcome = RetrievalOutcome(
            results: [result("a", sim: 0.80, ranges: [MosaicKit.TextRange(start: 0, end: 2)]),
                      result("b", sim: Float?.none, ranges: [MosaicKit.TextRange(start: 0, end: 2)]),  // keyword 独有
                      result("c", sim: 0.50, ranges: [])],
            trace: RetrievalTrace(query: "q", configVersion: "v", embeddingVersion: "e",
                                  indexVersion: "i"),
            keywordOnly: [], vectorOnly: [], bothCount: 0)
        let s = AbstentionSignals.from(outcome)
        r.expect(s.top1Similarity == 0.80, "top1 取最高相似度")
        r.expect(abs((s.margin ?? 0) - 0.30) < 1e-6,
                 "margin = 0.80 − 0.50 —— keyword 独有那条**没有**被当成 0 参与计算")
        r.expect(s.hasKeywordHit, "有字面命中")
        r.expect(s.candidateCount == 3, "候选数是全部结果")

        let empty = AbstentionSignals.from(RetrievalOutcome(
            results: [], trace: RetrievalTrace(query: "q", configVersion: "v",
                                               embeddingVersion: "e", indexVersion: "i"),
            keywordOnly: [], vectorOnly: [], bothCount: 0))
        r.expect(empty.top1Similarity == nil && empty.candidateCount == 0, "空结果不崩")
    }

    // MARK: 3 · 在 v3 上校准（真实 provider）

    static func calibrate(_ r: CheckRunner,
                          provider: any EmbeddingProvider,
                          label: String) async {
        r.suite("TD-10 · 在 synthetic-human-v3 上校准（正例零损失约束）· \(label)")

        guard let dataset = try? HumanLikeGoldenFixture.load() else {
            r.expect(false, "fixture 应当可加载"); return
        }

        let chunks = dataset.chunks
        let store = InMemoryVectorStore()
        // 批量嵌 —— 云端按请求计费，逐条发送会把成本乘以条数。
        for start in stride(from: 0, to: chunks.count, by: 32) {
            let batch = Array(chunks[start..<min(start + 32, chunks.count)])
            guard let vs = try? await provider.embed(batch: batch.map(\.text)) else { continue }
            for (c, v) in zip(batch, vs) {
                await store.upsert(EmbeddingRecord(ref: c.ref, chunkID: c.id,
                                                   chunkIndex: c.indexInBlock,
                                                   contentHash: c.contentHash,
                                                   embeddingVersion: provider.modelInfo.version,
                                                   chunkStrategy: c.strategy,
                                                   dimension: v.count, vector: v))
            }
        }
        let service = RetrievalService(provider: provider, vectors: store)
        let config = RetrievalConfig(version: "abstain-cal", mode: .hybrid,
                                     embeddingProvider: provider.modelInfo.identifier,
                                     embeddingVersion: provider.modelInfo.version,
                                     chunkStrategy: .default, topK: 10)

        // 只用 in-scope 正例：cross-language 是已知架构边界，
        // 把它算进「正例损失」会让阈值被一批本来就搜不到的用例绑住。
        let positives = dataset.cases.filter { $0.scope == .inScope }
        var posSignals: [AbstentionSignals] = []
        for c in positives {
            posSignals.append(AbstentionSignals.from(
                await service.retrieve(query: c.query, chunks: chunks, config: config)))
        }
        var negSignals: [AbstentionSignals] = []
        for n in dataset.negativeQueries {
            negSignals.append(AbstentionSignals.from(
                await service.retrieve(query: n.query, chunks: chunks, config: config)))
        }

        print("\n    ── TD-10 校准（\(label) · 正例 \(posSignals.count) / 负例 \(negSignals.count)）──")
        report(r, name: "绝对下限 similarityFloor", posSignals, negSignals) { $0.top1Similarity }
        report(r, name: "主力信号 margin (top1−top2)", posSignals, negSignals) { $0.margin }
        report(r, name: "比值 top1/mean(rest)", posSignals, negSignals) { $0.top1ToMeanRatio }

        r.expect(posSignals.allSatisfy { $0.candidateCount > 0 },
                 "每条正例都有候选 —— 否则不是阈值问题，是检索层问题")
        r.expect(negSignals.allSatisfy { $0.candidateCount > 0 },
                 "每条负例都返回了候选 —— 这就是 TD-10：语义可用时 .noResults 不可达")
        print("")
    }

    /// 报一个信号的可分性。**报余量，不只报最优点。**
    private static func report(_ r: CheckRunner, name: String,
                               _ pos: [AbstentionSignals], _ neg: [AbstentionSignals],
                               _ signal: (AbstentionSignals) -> Float?) {
        let p = pos.compactMap(signal).sorted()
        let n = neg.compactMap(signal).sorted()
        guard let posMin = p.first, let negMax = n.last, !n.isEmpty else {
            print("    \(name)：信号缺失，无法校准"); return
        }
        let gap = posMin - negMax
        // 正例零损失约束下的最优阈值 = 恰好等于正例最小值。
        let blocked = n.filter { $0 < posMin }.count
        let safety = blocked == 0 ? 0 : posMin - (n.filter { $0 < posMin }.max() ?? posMin)

        print(String(format: "    %@", name))
        print(String(format: "      正例 min %.4f / median %.4f    负例 max %.4f / median %.4f",
                     posMin, p[p.count / 2], negMax, n[n.count / 2]))
        print(String(format: "      完美分离间隙 %+.4f  →  %@", gap,
                     gap > 0 ? "存在完美阈值" : "重叠，没有完美阈值"))
        print(String(format: "      正例零损失时挡掉负例 %d/%d，到最近一条负例的余量 %.4f%@",
                     blocked, n.count, safety,
                     safety > 0 && safety < 0.01 ? "  ⚠️ 余量 < 0.01，不可发布" : ""))
        r.expect(true, "\(name) 的可分性已记录（正例零损失挡掉 \(blocked)/\(n.count)）")
    }

    /// 云端 provider 上的同一套校准。**这才是决策相关的那组数** ——
    /// 本地模型的余弦全挤在 0.93 附近，任何基于它的阈值都没有信号可用；
    /// 而生产候选是云端多语言模型。
    static func calibrateCloud(_ r: CheckRunner) async {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["MOSAIC_LIVE_EMBEDDING_BASE"], !base.isEmpty,
              let key = env["MOSAIC_LIVE_EMBEDDING_KEY"], !key.isEmpty,
              let model = env["MOSAIC_LIVE_EMBEDDING_MODEL"], !model.isEmpty,
              let dim = Int(env["MOSAIC_LIVE_EMBEDDING_DIM"] ?? "") else {
            r.suite("TD-10 · 云端校准")
            r.expect(true, "无云端凭据，跳过（结论：待验证，不编造阈值）")
            return
        }
        let provider = CloudEmbeddingProvider(baseURL: base, apiKey: key, model: model, dimension: dim)
        await calibrate(r, provider: provider, label: "云端 \(model)")
    }

    static func run(_ r: CheckRunner) async {
        checkJudge(r)
        checkSignalExtraction(r)
        if let local = try? LocalEmbedding.make() {
            await calibrate(r, provider: local, label: "本地 \(local.modelInfo.version)")
        } else {
            r.suite("TD-10 · 校准")
            r.expect(true, "本机无本地句向量模型，跳过（结论：待验证）")
        }
        await calibrateCloud(r)
    }
}
