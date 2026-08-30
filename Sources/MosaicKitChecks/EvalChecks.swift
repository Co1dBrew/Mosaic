import Foundation
import MosaicKit

/// Week 4 —— Golden Set · EvalRunner · Recall@K / MRR · Failure · Regression。
///
/// 跑在**真实 embedding** 之上（`NLEmbeddingProvider`）。这一点是刻意的：
/// mock provider 的伪向量会让 Recall 变成一个没有产品含义的数字。
enum EvalChecks {

    typealias F = RetrievalFoundationChecks

    /// 语料：8 篇笔记，每篇一个 block。
    static let notes: [(id: String, text: String)] = [
        ("delay",    "我问了 advisor 能不能延期一个学期毕业，他说要先跟系里确认"),
        ("policy",   "学生如需延期毕业，应在学期开始前四周向学院提交书面申请"),
        ("meeting",  "周会上说延期的事下周开会再定，毕业时间还有缓冲"),
        ("contract", "今天把合同评审的三处修改整理好了，法务反馈了三处"),
        ("book",     "读《人类简史》第四章，围绕认知革命展开"),
        ("photo",    "现场照片：设备安装位置与线路走向"),
        ("schedule", "下午三点和产品过一遍 Q3 排期"),
        ("noodle",   "楼下那家面馆的辣椒油很香")
    ]

    static func chunks() -> [NoteChunk] {
        notes.enumerated().flatMap { i, note in
            ChunkPipeline.chunks(noteID: note.id,
                                 blocks: [F.textBlock("B\(i)", note.text, order: 0)],
                                 strategy: .block)
        }
    }

    /// Golden Set：混合精确 query 与自然语言 query，覆盖两种检索路径。
    static func goldenSet() -> [EvalCase] {
        [
            EvalCase(id: "g1", query: "延期毕业", expectedNoteIDs: ["delay"], note: "精确关键词"),
            EvalCase(id: "g2", query: "我之前问学校能不能晚一点毕业的事情", expectedNoteIDs: ["delay"], note: "自然语言，字面几乎不重合"),
            EvalCase(id: "g3", query: "合同要改哪些地方", expectedNoteIDs: ["contract"], note: "自然语言"),
            EvalCase(id: "g4", query: "认知革命", expectedNoteIDs: ["book"], note: "精确关键词"),
            EvalCase(id: "g5", query: "排期会议", expectedNoteIDs: ["schedule"], note: "近义"),
            EvalCase(id: "g6", query: "设备安装", expectedNoteIDs: ["photo"], note: "精确关键词"),
            // 期望一篇语料里根本不存在的笔记 —— 这是**确定**会失败的用例。
            // 靠语义构造「必定失败」在 8 篇语料上不可靠：Top 5 覆盖了八分之五，
            // 随手一条无意义 query 也可能蒙对。这同时是真实场景：笔记被删了，
            // 或者 missingData。
            EvalCase(id: "g7", query: "完全不存在的内容 xyzzy",
                     expectedNoteIDs: ["note-that-does-not-exist"], note: "刻意的失败用例")
        ]
    }

    static func makeService() async -> (RetrievalService, RetrievalConfig)? {
        guard let provider = try? LocalEmbedding.make() else { return nil }
        let store = InMemoryVectorStore()
        for c in chunks() {
            guard let v = try? await provider.embed(c.text) else { continue }
            await store.upsert(EmbeddingRecord(ref: c.ref, chunkID: c.id, chunkIndex: c.indexInBlock,
                                               contentHash: c.contentHash,
                                               embeddingVersion: provider.modelInfo.version,
                                               dimension: provider.modelInfo.dimension, vector: v))
        }
        let config = RetrievalConfig(version: "retrieval-v1", mode: .hybrid,
                                     embeddingProvider: provider.modelInfo.identifier,
                                     embeddingVersion: provider.modelInfo.version,
                                     chunkStrategy: .block, topK: 10)
        return (RetrievalService(provider: provider, vectors: store), config)
    }

    // MARK: 1 · 指标口径

    static func checkMetrics(_ r: CheckRunner) async {
        r.suite("Week4 · 指标口径 —— Recall@K / MRR / No-result / P50 / P95")

        guard let (service, config) = await makeService() else {
            r.expect(true, "本机无本地句向量模型，跳过")
            return
        }
        let runner = EvalRunner(service: service, chunksProvider: { chunks() })
        let run = try? await runner.run(cases: goldenSet(), config: config)
        guard let run else { r.expect(false, "评测应当成功"); return }

        r.expect(run.metrics.caseCount == 7, "全部用例被执行")
        r.expect(run.metrics.relevantCaseCount == 7 && run.metrics.noResultCaseCount == 0,
                 "正例与负例分母明确分开")
        r.expect(run.recallInRange, "Recall 全部落在 [0,1]")
        r.expect(run.metrics.recallAt1 <= run.metrics.recallAt3, "Recall@1 ≤ Recall@3（单调）")
        r.expect(run.metrics.recallAt3 <= run.metrics.recallAt5, "Recall@3 ≤ Recall@5（单调）")
        r.expect(run.metrics.mrr >= 0 && run.metrics.mrr <= 1, "MRR 落在 [0,1]")
        r.expect(run.metrics.p50Ms > 0, "P50 被真实测量")
        r.expect(run.metrics.p95Ms >= run.metrics.p50Ms, "P95 ≥ P50")

        // g7 是刻意造的失败用例，必须被抓出来。
        r.expect(run.failures.contains { $0.evalCase.id == "g7" },
                 "刻意构造的失败用例被收集（实际失败：\(run.failures.map(\.evalCase.id).joined(separator: ",")))")
        r.expect(run.failures.allSatisfy { !$0.isTriaged }, "新失败默认未归因 —— 等人工标注")

        // 严格口径：多个 expected 时必须**全部**命中。
        //
        // 第二个 expected 用一个**语料里根本不存在**的 id，而不是「一篇大概搜不到的
        // 笔记」。原来用的是后者，于是这条断言实际依赖「检索找不到 noodle」——
        // CJK 切分改进之后 noodle 被找到了，断言随之失败，而它想测的
        // **指标口径**其实一点没变。测口径就该把检索行为这个变量消掉。
        let strict = EvalCase(query: "延期毕业", expectedNoteIDs: ["delay", "does-not-exist"])
        let strictRun = try? await runner.run(cases: [strict], config: config)
        r.expect(strictRun?.metrics.recallAt5 == 0,
                 "多个 expected 时必须全部命中才算通过 —— 宽松口径会让「找到一半」看起来和「全找到」一样好")

        // 反向：两个 expected 都在语料里且都能被找到时，必须算通过。
        // 只测「不通过」的一侧，一个恒返回 0 的实现也能过。
        let bothFound = EvalCase(query: "延期", expectedNoteIDs: ["delay"])
        let bothRun = try? await runner.run(cases: [bothFound], config: config)
        r.expect(bothRun?.metrics.recallAt5 == 1, "单个 expected 命中时算通过")

        // 负例进入同一个 Runner，但不污染 Recall / MRR。严格口径是结果列表为空。
        let negative = EvalCase(id: "n1", query: "护照换发材料",
                                expectation: .noRelevantResult)
        let keywordConfig = RetrievalConfig(version: "negative-keyword", mode: .keyword,
                                             embeddingProvider: config.embeddingProvider,
                                             embeddingVersion: config.embeddingVersion,
                                             chunkStrategy: .block, topK: 10)
        let negativeKeyword = try? await runner.run(cases: [negative], config: keywordConfig)
        r.expect(negativeKeyword?.metrics.relevantCaseCount == 0
                 && negativeKeyword?.metrics.noResultCaseCount == 1,
                 "负例不进入 Recall 分母")
        r.expect(negativeKeyword?.metrics.noResultAccuracy == 1
                 && negativeKeyword?.metrics.falsePositiveRate == 0,
                 "keyword 空结果：No-result Accuracy 100%，FPR 0%")
        r.expect(negativeKeyword?.failures.isEmpty == true, "正确返回空列表的负例不收为失败")

        let negativeHybrid = try? await runner.run(cases: [negative], config: config)
        r.expect(negativeHybrid?.metrics.noResultAccuracy == 0
                 && negativeHybrid?.metrics.falsePositiveRate == 1,
                 "无相关性下限时 hybrid 误召回：No-result Accuracy 0%，FPR 100%")
        r.expect(negativeHybrid?.failures.first?.evalCase.id == "n1",
                 "负例误召回进入 Failure Inspection")

        print("\n    ── Golden Set 实测（真实 embedding · \(notes.count) 篇笔记 / \(goldenSet().count) 条 query）──")
        print(String(format: "    Recall@1 = %.3f   Recall@3 = %.3f   Recall@5 = %.3f   MRR = %.3f",
                     run.metrics.recallAt1, run.metrics.recallAt3, run.metrics.recallAt5, run.metrics.mrr))
        print(String(format: "    P50 = %.2f ms   P95 = %.2f ms   失败 %d 条",
                     run.metrics.p50Ms, run.metrics.p95Ms, run.failures.count))
        print("")

        // SLO 检查（检索本身，不含 UI）。
        r.expect(run.metrics.p95Ms < 250,
                 "P95 在 SLO 预算内（实测 \(String(format: "%.1f", run.metrics.p95Ms)) ms）")
    }

    // MARK: 2 · 取消与进度

    static func checkRunnerControl(_ r: CheckRunner) async {
        r.suite("Week4 · EvalRunner —— 进度与取消")

        guard let (service, config) = await makeService() else {
            r.expect(true, "跳过（无本地模型）"); return
        }
        let runner = EvalRunner(service: service, chunksProvider: { chunks() })

        // 进度回调逐条推进。
        let collector = ProgressCollector()
        _ = try? await runner.run(cases: goldenSet(), config: config) { p in
            Task { await collector.record(p.done, p.total) }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let seen = await collector.values
        r.expect(seen.count == goldenSet().count, "每条用例回调一次（\(seen.count)）")
        r.expect(seen.last?.0 == goldenSet().count, "最后一次回调 done == total")

        // 取消：不留半份结果。
        let task = Task { try await runner.run(cases: goldenSet(), config: config) }
        task.cancel()
        var cancelled = false
        do { _ = try await task.value } catch is CancellationError { cancelled = true } catch { }
        r.expect(cancelled, "取消抛出 CancellationError —— 半份指标比没有指标更危险")
    }

    // MARK: 3 · Config 对比

    static func checkComparison(_ r: CheckRunner) {
        r.suite("Week4 · Config 对比 —— 同时看到质量与延迟")

        let current = EvalMetrics(caseCount: 40, recallAt1: 0.700, recallAt3: 0.825,
                                  recallAt5: 0.875, mrr: 0.781, p50Ms: 96, p95Ms: 181)
        let baseline = EvalMetrics(caseCount: 40, recallAt1: 0.650, recallAt3: 0.800,
                                   recallAt5: 0.825, mrr: 0.742, p50Ms: 88, p95Ms: 154)
        let deltas = EvalComparison.compare(current: current, baseline: baseline)

        r.expect(deltas.count == 6, "六项指标全部对比")
        r.expect(deltas.contains { $0.polarity == .lowerIsBetter },
                 "延迟与质量在同一张表里 —— 分开放会让人只看 Recall 就下结论")

        let recall5 = deltas.first { $0.label == "Recall@5" }!
        r.expect(recall5.direction == .better, "Recall@5 上升判为更好")
        r.expect(recall5.deltaText == "+0.050", "delta 文案正确（\(recall5.deltaText)）")

        let p95 = deltas.first { $0.label == "P95" }!
        r.expect(p95.direction == .worse, "P95 上升判为更差（越小越好）")
        r.expect(p95.deltaText == "+27 ms", "延迟 delta 带单位（\(p95.deltaText)）")

        // 无变化不误报方向。
        let same = EvalComparison.compare(current: current, baseline: current)
        r.expect(same.allSatisfy { $0.direction == .unchanged }, "与自身对比全部 unchanged")

        // 一句话 trade-off，**不给 PASS/FAIL**。
        let summary = EvalComparison.tradeoffSummary(deltas)
        r.expect(summary.contains("质量提升") && summary.contains("延迟回退"),
                 "同时点出质量提升与延迟回退（\(summary.prefix(20))…）")
        r.expect(!summary.contains("PASS") && !summary.contains("FAIL"),
                 "Eval 不下判定 —— 判定是 Release Gate 的事")
        r.expect(EvalComparison.tradeoffSummary(same).contains("基本一致"), "无差异时如实说明")
    }

    // MARK: 4 · Failure Inspection 与 Regression 闭环

    static func checkRegressionLoop(_ r: CheckRunner) async {
        r.suite("Week4 · Regression 闭环 —— 失败 → 归因 → 回归集 → 通过率")

        guard let (service, config) = await makeService() else {
            r.expect(true, "跳过（无本地模型）"); return
        }
        let runner = EvalRunner(service: service, chunksProvider: { chunks() })
        guard let run = try? await runner.run(cases: goldenSet(), config: config),
              var failure = run.failures.first else {
            r.expect(false, "应当至少有一条失败用例"); return
        }

        // 失败证据齐全 —— 三路各自的名次是归因的依据。
        r.expect(!failure.returnedNoteIDs.isEmpty || failure.hybridRank == nil,
                 "失败用例记录了实际返回")
        r.expect(FailureType.allCases.count == 7, "失败类型固定 7 类，不可自由输入")
        r.expect(FailureType.chunking.evidenceHint.contains("切"), "每类都给出典型证据提示")

        // 人工归因。
        failure.failureType = .embedding
        failure.diagnosisNote = "vector 排名很低但语义明显相关"
        r.expect(failure.isTriaged, "标注后视为已归因")

        // 加入回归集，且幂等。
        var regression = RegressionSet()
        r.expect(regression.add(failure), "首次加入成功")
        r.expect(!regression.add(failure), "重复加入被拒绝 —— 否则反复点击会让 Pass Rate 分母虚高")
        r.expect(regression.count == 1, "集合里只有一条")
        r.expect(regression.contains(failure), "可查询是否已在集合中")
        r.expect(regression.cases[0].source == .regression, "来源标记为 regression")
        r.expect(regression.cases[0].sourceFailureType == .embedding, "归因随用例保留，可用于统计")

        // 下一次 Eval **自动**带上回归集 —— 不需要单独触发。
        let combined = goldenSet() + regression.cases
        guard let run2 = try? await runner.run(cases: combined, config: config) else {
            r.expect(false, "合并跑批应当成功"); return
        }
        r.expect(run2.goldenMetrics.caseCount == goldenSet().count, "Golden 部分单独统计")
        r.expect(run2.regressionMetrics.caseCount == regression.count, "Regression 部分单独统计")
        r.expect(run2.metrics.caseCount == combined.count, "整体统计覆盖两部分")

        // Pass Rate 与 Recall@5 同口径。
        r.expect(run2.regressionPassRate == run2.regressionMetrics.recallAt5,
                 "Regression Pass Rate 与 Recall@5 同口径 —— 避免两套「通过」定义")

        // 空集合视为 1.0：没有回归用例就没有回归。
        let noRegression = EvalRun(configVersion: "v", embeddingVersion: "e",
                                   metrics: .zero, goldenMetrics: .zero,
                                   regressionMetrics: .zero, failures: [])
        r.expect(noRegression.regressionPassRate == 1.0, "回归集为空时 Pass Rate = 1.0")

        // 归因统计 —— 固定 7 类的全部意义。
        let breakdown = run2.failureBreakdown()
        r.expect(breakdown.allSatisfy { $0.count > 0 }, "统计只包含已归因的失败")

        // 删除。
        regression.remove(id: regression.cases[0].id)
        r.expect(regression.count == 0, "可从回归集移除")
    }

    // MARK: 5 · 数据集（D5 的 Dataset 选择器）

    static func checkDataset(_ r: CheckRunner) {
        r.suite("Week4 · EvalDataset —— Golden / Regression 同一套口径")

        var dataset = EvalDataset(golden: goldenSet())
        r.expect(dataset.count(.golden) == 7, "Golden 用例数")
        r.expect(dataset.count(.regression) == 0, "初始回归集为空")
        r.expect(dataset.count(.both) == 7, "合并 = 两部分之和")

        // 幂等，且判重口径与 RegressionSet.add 一致。
        r.expect(dataset.addGolden(query: " 新的 query ", expectedNoteIDs: ["delay"]), "可加入 Golden 用例")
        r.expect(!dataset.addGolden(query: "新的 query", expectedNoteIDs: ["delay"]),
                 "同 query + 同期望重复加入被拒绝 —— 与 RegressionSet 同一套判重口径")
        r.expect(dataset.addGolden(query: "新的 query", expectedNoteIDs: ["delay", "policy"]),
                 "期望集合不同则是另一条用例")
        r.expect(!dataset.addGolden(query: "   ", expectedNoteIDs: ["delay"]), "空 query 不入集")
        r.expect(dataset.addGolden(query: "有 query 没期望", expectedNoteIDs: []),
                 "空 expected 的旧调用明确迁移为 noRelevantResult")
        r.expect(!dataset.addGolden(query: " 有 query 没期望 ", expectation: .noRelevantResult),
                 "负例按 trim 后 query + expectation 幂等")
        r.expect(!dataset.addGolden(query: "坏正例", expectation: .relevant(noteIDs: [])),
                 "空 relevant 仍是非法标注，不能与负例混淆")
        r.expect(dataset.golden.last?.query == "有 query 没期望", "入集前 trim")
        r.expect(dataset.golden.last?.expectation == .noRelevantResult, "负例意图被显式保存")
        r.expect(dataset.golden.allSatisfy { $0.source == .golden }, "来源标记为 golden")

        // 选择器返回的用例带正确的 source，所以两部分指标在任何选择下都能分开统计。
        let failure = EvalFailure(evalCase: EvalCase(query: "回归用例", expectedNoteIDs: ["policy"]),
                                  returnedNoteIDs: [], keywordRank: nil, vectorRank: nil, hybridRank: nil,
                                  failureType: .keyword)
        r.expect(dataset.addRegression(failure), "失败用例可加入回归集")
        r.expect(!dataset.addRegression(failure), "回归集加入幂等")
        r.expect(dataset.regressionContains(failure), "可查询是否已在回归集中")
        r.expect(dataset.cases(.regression).allSatisfy { $0.source == .regression }, "回归部分来源正确")
        r.expect(dataset.cases(.both).filter { $0.source == .regression }.count == 1,
                 "合并后仍能按 source 区分 —— EvalRun 的分部统计靠它")

        // 编解码：Developer Tools 侧要落盘。
        if let data = try? JSONEncoder().encode(dataset),
           let back = try? JSONDecoder().decode(EvalDataset.self, from: data) {
            r.expect(back == dataset, "可 JSON 往返 —— 数据集要能持久化")
        } else {
            r.expect(false, "可 JSON 往返 —— 数据集要能持久化")
        }

        let legacy = #"{"id":"legacy","query":"旧数据","expectedNoteIDs":["delay"],"source":"golden","addedAt":0}"#
        if let oldCase = try? JSONDecoder().decode(EvalCase.self, from: Data(legacy.utf8)) {
            r.expect(oldCase.expectation == .relevant(noteIDs: ["delay"]),
                     "升级后可读取只有 expectedNoteIDs 的旧设备数据")
        } else {
            r.expect(false, "旧 EvalCase JSON 必须可迁移读取")
        }

        // 用例引用的笔记被删了 —— 那不是检索质量的问题，UI 必须能区分。
        let dangling = EvalDataset.danglingCases(dataset.cases(.both),
                                                 existingNoteIDs: Set(notes.map(\.id)))
        r.expect(dangling.contains { $0.id == "g7" },
                 "引用了不存在的笔记的用例被标出来 —— 它永远失败，但原因不是检索")
        r.expect(!dangling.contains { $0.id == "g1" }, "引用有效笔记的用例不算 dangling")

        let count = dataset.count(.golden)
        dataset.removeGolden(id: dataset.golden[0].id)
        r.expect(dataset.count(.golden) == count - 1, "可删除 Golden 用例")
        dataset.removeRegression(id: dataset.regression.cases[0].id)
        r.expect(dataset.count(.regression) == 0, "可删除回归用例")
    }

    static func run(_ r: CheckRunner) async {
        await checkMetrics(r)
        await checkRunnerControl(r)
        checkComparison(r)
        await checkRegressionLoop(r)
        checkDataset(r)
    }
}

private extension EvalRun {
    var recallInRange: Bool {
        [metrics.recallAt1, metrics.recallAt3, metrics.recallAt5].allSatisfy { $0 >= 0 && $0 <= 1 }
    }
}

actor ProgressCollector {
    private(set) var values: [(Int, Int)] = []
    func record(_ done: Int, _ total: Int) { values.append((done, total)) }
}
