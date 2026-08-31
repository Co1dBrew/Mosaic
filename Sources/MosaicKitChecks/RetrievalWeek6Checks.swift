import Foundation
import MosaicKit

/// Week 6 —— 对照实验（6.1 / 6.2）· 规模复测（6.3）· Staleness（6.4）·
/// Regression 长跑（6.5）· 无障碍朗读顺序（6.6）。
///
/// 这一套的产出**是数字，不是断言数量**。每个实验都会把实测表打印出来，
/// 供 `RETRIEVAL_ARCHITECTURE.md` 与 backlog 回填 —— 那些位置此前写的是「待测」。
///
/// ⚠️ 所有数字都是**在这台 Mac 上、这个构建模式下**测的。
/// iPhone 真机数字一定不同，必须单独复测（TD-9 / §9.7 的同一条纪律）。
enum RetrievalWeek6Checks {

    typealias E = EvalChecks

    static var buildMode: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    // MARK: 语料

    /// 6.2 专用的**长文语料**。
    ///
    /// 这不是为了让表格好看：`EvalChecks` 的 8 篇笔记每篇都不到 240 字，
    /// 三种策略在它们上面切出来的 chunk **完全一样**，于是三行数字也完全一样 ——
    /// 那种表格看起来像结论，实际上什么都没测到。要让 chunk 策略产生差异，
    /// 语料必须长到需要切分，而且答案要埋在**中段**（埋在开头的话，
    /// 任何策略的第一个 chunk 都含有它）。
    static let longFormNotes: [(id: String, text: String)] = [
        ("thesis", String(repeating: "这一段讲的是文献综述的组织方式，先按时间线后按方法论。", count: 24)
            + "关于延期毕业的具体流程，需要在学期开始前四周向学院提交书面申请，并附上导师签字的说明。"
            + String(repeating: "后面这一段回到实验设计，讨论对照组的选取与样本量估计。", count: 24)),
        ("standup", String(repeating: "上半段是各人的日常同步，进度、阻塞、今天计划，内容零散。", count: 24)
            + "会议后段确定了 Q3 排期结论：核心功能十月中冻结，回归测试留两周，发布定在十一月第一周。"
            + String(repeating: "再往后是关于工具链升级的讨论，与排期无关。", count: 24)),
        ("manual", String(repeating: "设备说明书前面讲的是安全须知与包装清单。", count: 24)
            + "线路走向：主电缆从左侧槽位进入，接地线单独走右侧，避免与信号线并行。"
            + String(repeating: "最后是保修条款与联系方式。", count: 24))
    ]

    /// 答案都埋在中段，且 query 与目标句字面重合很少 —— 这样切分方式才会真的影响结果。
    static func longFormGoldenSet() -> [EvalCase] {
        [
            EvalCase(id: "L1", query: "晚一点毕业要提前多久申请", expectedNoteIDs: ["thesis"]),
            EvalCase(id: "L2", query: "发布时间定在什么时候", expectedNoteIDs: ["standup"]),
            EvalCase(id: "L3", query: "接地线怎么走", expectedNoteIDs: ["manual"])
        ]
    }

    // MARK: 共用：为某套 chunk 策略建一份索引

    static func environment(strategy: ChunkStrategy,
                            provider: any EmbeddingProvider,
                            notes: [(id: String, text: String)] = E.notes) async throws -> (RetrievalService, [NoteChunk]) {
        let chunks = notes.enumerated().flatMap { i, note in
            ChunkPipeline.chunks(noteID: note.id,
                                 blocks: [RetrievalFoundationChecks.textBlock("B\(i)", note.text, order: 0)],
                                 strategy: strategy)
        }
        let store = InMemoryVectorStore()
        // 批量嵌入：云端按请求计费，逐条发送会把成本乘以条数。
        let vectors = try await provider.embed(batch: chunks.map(\.text))
        for (chunk, vector) in zip(chunks, vectors) {
            await store.upsert(EmbeddingRecord(ref: chunk.ref, chunkID: chunk.id,
                                               chunkIndex: chunk.indexInBlock,
                                               contentHash: chunk.contentHash,
                                               embeddingVersion: provider.modelInfo.version,
                                               chunkStrategy: strategy.identity,
                                               dimension: vector.count, vector: vector))
        }
        return (RetrievalService(provider: provider, vectors: store), chunks)
    }

    static func config(_ version: String, strategy: ChunkStrategy, provider: any EmbeddingProvider) -> RetrievalConfig {
        RetrievalConfig(version: version, mode: .hybrid,
                        embeddingProvider: provider.modelInfo.identifier,
                        embeddingVersion: provider.modelInfo.version,
                        chunkStrategy: strategy, topK: 10)
    }

    // MARK: 6.2 · Chunk 策略对比实验

    static func checkChunkStrategyExperiment(_ r: CheckRunner) async {
        r.suite("Week6 · 6.2 Chunk 策略对比 —— 三种策略的 Recall@5")

        guard let provider = try? LocalEmbedding.make() else {
            r.expect(true, "本机无本地句向量模型，跳过（结论：待验证）")
            return
        }

        let strategies: [(String, ChunkStrategy)] = [
            ("block", .block),
            ("fixed(240/40)", .default),
            ("sentence(240)", .sentence(maxChars: 240))
        ]
        // 语料 = 8 篇短笔记 + 3 篇长笔记；用例 = 短语料的 7 条 + 长语料的 3 条。
        // 混在一起跑是刻意的：只跑长语料等于换了一个更容易的题目，
        // 而生产语料里两种笔记都有。
        let notes = E.notes + longFormNotes
        let cases = E.goldenSet() + longFormGoldenSet()

        var chunkCounts: [String: Int] = [:]
        for (label, strategy) in strategies {
            chunkCounts[label] = notes.enumerated().reduce(0) { acc, entry in
                acc + ChunkPipeline.chunks(noteID: entry.element.id,
                                           blocks: [RetrievalFoundationChecks.textBlock("B\(entry.offset)",
                                                                                        entry.element.text, order: 0)],
                                           strategy: strategy).count
            }
        }

        let arms = strategies.map { label, strategy in
            RetrievalExperiment.Arm(label: "\(label) · \(chunkCounts[label] ?? 0) chunks",
                                    config: config("chunk-\(label)", strategy: strategy, provider: provider)) {
                try await environment(strategy: strategy, provider: provider, notes: notes)
            }
        }

        guard let report = try? await RetrievalExperiment.run(title: "Chunk 策略",
                                                             cases: cases,
                                                             arms: arms) else {
            r.expect(false, "实验应当跑完 —— 少一臂的对照表比没有表更危险")
            return
        }

        print("\n    ── 6.2 Chunk 策略对比（\(buildMode) · \(notes.count) 篇笔记 / \(report.caseCount) 条 query · 真实 NLEmbedding）──")
        print(report.markdownTable().split(separator: "\n").map { "    " + $0 }.joined(separator: "\n"))
        if Set(chunkCounts.values).count == 1 {
            print("    ⚠️ 三种策略切出的 chunk 数相同 —— 语料太短，这次实验没有区分度，结论：待验证")
        }
        // 把每一臂失败的用例打出来。三臂 Recall 相同但失败的是同一批时，
        // 结论是「换切分解决不了这批用例」，而不是「三种切分一样好」——
        // 这两句话对下一步该做什么的指示完全相反。
        let longIDs = Set(longFormGoldenSet().map(\.query))
        for arm in report.arms {
            let longFailures = arm.failureQueries.filter { longIDs.contains($0) }
            print("    \(arm.label) 失败 \(arm.failureQueries.count) 条，其中长文用例 \(longFailures.count)/\(longIDs.count)")
        }
        if report.arms.allSatisfy({ $0.failureQueries.filter { longIDs.contains($0) }.count == longIDs.count }) {
            print("    ⚠️ 长文用例在三种策略下**全部失败** —— 这不是切分策略的问题。")
            print("       与既有登记项一致：`NLEmbedding` 对长文本的稳定性未验证（见 §13 技术债表）。")
            print("       结论：**换 chunk 策略解决不了这批用例**，需要换模型或补词法信号。待进一步验证。")
        }
        print("")

        r.expect(report.arms.count == 3, "三种策略各跑一臂")
        r.expect(Set(chunkCounts.values).count > 1,
                 "语料长到能让三种策略切出不同的 chunk 数（\(strategies.map { "\($0.0)=\(chunkCounts[$0.0] ?? 0)" }.joined(separator: " · "))）—— 否则这张表没有区分度")
        r.expect(report.arms.allSatisfy { $0.metrics.caseCount == cases.count },
                 "每一臂跑的是同一批用例 —— 否则 delta 里混进「分母变了」")
        r.expect(report.arms.allSatisfy { (0...1).contains($0.metrics.recallAt5) }, "Recall 落在 [0,1]")
        r.expect(report.leader != nil, "能指出这批用例上数字最高的一臂")
        r.expect(Set(report.arms.map(\.metrics.recallAt5)).count > 1
                    || Set(report.arms.map(\.metrics.mrr)).count > 1,
                 "三臂的数字不完全相同 —— 完全相同说明策略没有真正被测到")
        // **不断言哪一种策略更好** —— 8 篇笔记上的差异没有统计效力，
        // 把某一次的胜者写成断言，下次语料一变就是一条假失败。
        r.expect(report.arms.allSatisfy { $0.indexBuildMs > 0 },
                 "建索引耗时被单独测量 —— 它不计入 P50/P95，但换策略时它本身就是成本")
    }

    // MARK: 6.1a · Hybrid vs Keyword Baseline —— PRD 的核心主张

    /// **这是整个 Goal 1 要回答的那个问题**：语义检索到底比关键词检索好多少？
    ///
    /// 三臂跑**同一批用例、同一份语料、同一套 chunk 策略**，只换 `mode`：
    /// keyword（baseline）· vector · hybrid。这样比出来的才是策略差异 ——
    /// 三种 mode 共用一条管线（`RetrievalService`），所以也不会混进实现差异。
    ///
    /// ⚠️ **样本量警告**：7 条 query / 8 篇笔记。**一条用例翻面 = 0.143 的跳动**，
    /// 所以下面的百分比**不能当作产品结论**，只能当作「管线通了、方向对了」的证据。
    /// 真正的结论要等 Golden Set 扩到 PRD v1.0 规定的规模。
    static func checkHybridVsKeywordBaseline(_ r: CheckRunner) async {
        r.suite("Week6 · 6.1a Hybrid vs Keyword Baseline —— 语义到底提升了多少")

        guard let provider = try? LocalEmbedding.make() else {
            r.expect(true, "本机无本地句向量模型，跳过（结论：待验证）")
            return
        }

        let modes: [(String, RetrievalMode)] = [
            ("keyword（baseline）", .keyword),
            ("vector", .vector),
            ("hybrid", .hybrid)
        ]
        let arms = modes.map { label, mode in
            var config = config("mode-\(mode.rawValue)", strategy: .block, provider: provider)
            config.mode = mode
            return RetrievalExperiment.Arm(label: label, config: config) {
                // keyword 臂也建索引 —— 建索引耗时可比，且这一列本来就要如实反映
                // 「上语义要多付什么」。keyword 路不会去读它。
                try await environment(strategy: .block, provider: provider)
            }
        }

        guard let report = try? await RetrievalExperiment.run(title: "Retrieval Mode",
                                                             cases: E.goldenSet(),
                                                             arms: arms) else {
            r.expect(false, "实验应当跑完"); return
        }

        let keyword = report.arms[0].metrics
        let hybrid = report.arms[2].metrics

        print("\n    ── 6.1a Hybrid vs Keyword（\(buildMode) · \(E.notes.count) 篇笔记 / \(report.caseCount) 条 query · 真实 NLEmbedding）──")
        print(report.markdownTable().split(separator: "\n").map { "    " + $0 }.joined(separator: "\n"))

        func lift(_ new: Double, _ base: Double) -> String {
            guard base > 0 else { return new > 0 ? "baseline 为 0，无法算相对提升" : "持平" }
            return String(format: "%+.1f%%（绝对 %+.3f）", (new - base) / base * 100, new - base)
        }
        print("\n    Hybrid vs Keyword baseline：")
        print("      Recall@1  \(lift(hybrid.recallAt1, keyword.recallAt1))")
        print("      Recall@3  \(lift(hybrid.recallAt3, keyword.recallAt3))")
        print("      Recall@5  \(lift(hybrid.recallAt5, keyword.recallAt5))")
        print("      MRR       \(lift(hybrid.mrr, keyword.mrr))")
        print(String(format: "      P95       %.2f ms → %.2f ms（语义路要多付一次 query embedding）",
                     keyword.p95Ms, hybrid.p95Ms))
        print("    ⚠️ n=\(report.caseCount)：一条用例翻面 = \(String(format: "%.3f", 1.0 / Double(report.caseCount))) 的跳动。")
        print("       这不是产品结论，是「管线通了」的证据。真正的结论要等 Golden Set 扩到 PRD 规定的规模。\n")

        r.expect(report.arms.count == 3, "keyword / vector / hybrid 三臂")
        r.expect(report.arms.allSatisfy { $0.metrics.caseCount == E.goldenSet().count },
                 "三臂跑同一批用例")
        r.expect(hybrid.recallAt5 >= keyword.recallAt5,
                 String(format: "Hybrid 的 Recall@5 不低于 keyword baseline（%.3f vs %.3f）—— 若相反，说明融合把单路的好结果挤掉了",
                        hybrid.recallAt5, keyword.recallAt5))
        r.expect(hybrid.mrr >= keyword.mrr,
                 String(format: "Hybrid 的 MRR 不低于 keyword baseline（%.3f vs %.3f）", hybrid.mrr, keyword.mrr))
        // **不断言提升幅度。** 7 条用例上的百分比没有统计效力，
        // 把某一次的数字写成断言，下次语料一变就是一条假失败。
        r.expect(hybrid.p95Ms >= keyword.p95Ms,
                 "Hybrid 比 keyword 慢 —— 多一次 query embedding，这是语义路的固定成本")
    }

    // MARK: 6.2 附带发现 · 余弦受文本长度支配（TD-11）

    /// 6.2 跑出「三种策略下长文用例全部失败」之后追下去测到的东西。
    ///
    /// **结论：`NLEmbedding` 的余弦相似度主要由文本长度决定，而不是相关性。**
    /// 把同一段文字重复 n 次拉长，余弦单调下降约 0.05；而相关文本与无关文本
    /// 在同一长度上的差距只有 0.001–0.015 —— **长度效应比相关性效应大一个数量级。**
    ///
    /// 三个直接后果：
    ///
    /// 1. **长笔记天然吃亏。** 这解释了 6.2 里换切分也救不回来的那三条用例：
    ///    对手是 13 个字的「面馆」笔记，它靠短就赢了。
    /// 2. **TD-10 的相关性下限不能只看余弦。** 早先已知「余弦绝对值没有解释力」，
    ///    现在知道了它为什么没有：它被长度混淆了。任何形如 `similarity > x` 的
    ///    阈值都会变成一个隐蔽的长度过滤器。
    /// 3. **切分到相近长度不只是 recall 特性，也是可比性要求**（D-RT-014 的补充）。
    ///
    /// 这里**不实现任何长度归一化** —— 那是一次没有 Golden Set 支撑的模型层改动，
    /// 属于范围扩张。这条断言的作用是把现象钉住，换模型时它会立刻告诉你变没变。
    static func checkCosineLengthBias(_ r: CheckRunner) async {
        r.suite("Week6 · TD-11 余弦受文本长度支配（6.2 的追因）")

        guard let provider = try? LocalEmbedding.make() else {
            r.expect(true, "本机无本地句向量模型，跳过（结论：待验证）")
            return
        }
        func cosine(_ a: [Float], _ b: [Float]) -> Float { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }

        let query = try? await provider.embed("晚一点毕业要提前多久申请")
        guard let query else { r.expect(false, "query 可嵌入"); return }
        let relevant = "关于延期毕业的具体流程，需要在学期开始前四周向学院提交书面申请。"
        let irrelevant = "楼下那家面馆的辣椒油很香。"

        var rows: [(n: Int, rel: Float, irr: Float, chars: Int)] = []
        for n in [1, 2, 4, 8, 16] {
            let r1 = String(repeating: relevant, count: n)
            let r2 = String(repeating: irrelevant, count: n)
            guard let v1 = try? await provider.embed(r1), let v2 = try? await provider.embed(r2) else { continue }
            rows.append((n, cosine(query, v1), cosine(query, v2), r1.count))
        }
        guard rows.count == 5 else { r.expect(false, "五档长度都测到"); return }

        print("\n    ── TD-11 长度偏置（\(buildMode) · \(provider.modelInfo.version)）──")
        print("     重复次数   相关文本 cos   无关文本 cos   相关文本字数")
        for row in rows {
            print(String(format: "     %2d         %.4f         %.4f        %d", row.n, row.rel, row.irr, row.chars))
        }
        let lengthEffect = rows[0].rel - rows[rows.count - 1].rel
        let relevanceEffect = rows.map { abs($0.rel - $0.irr) }.max() ?? 0
        print(String(format: "     长度效应 %.4f   相关性效应（最大）%.4f   → 相差 %.1f 倍\n",
                     lengthEffect, relevanceEffect, Double(lengthEffect / max(relevanceEffect, 1e-6))))

        r.expect(rows.map(\.rel) == rows.map(\.rel).sorted(by: >),
                 "同一段文字越长，余弦越低 —— 单调，不是噪声")
        r.expect(lengthEffect > relevanceEffect * 2,
                 String(format: "长度效应（%.4f）显著大于相关性效应（%.4f）—— 任何 `similarity > x` 的阈值都会变成隐蔽的长度过滤器",
                        lengthEffect, relevanceEffect))
        r.expect(rows.contains { $0.irr > $0.rel },
                 "存在「无关但更短」的文本余弦高于「相关但更长」的文本 —— 这就是 6.2 里长文用例全败的原因")
    }

    // MARK: 6.1 · Local vs Cloud embedding 对比实验

    static func checkLocalVsCloudExperiment(_ r: CheckRunner) async {
        r.suite("Week6 · 6.1 Local vs Cloud embedding 对比")

        guard let local = try? LocalEmbedding.make() else {
            r.expect(true, "本机无本地句向量模型，跳过（结论：待验证）")
            return
        }

        // 第一组对照永远可跑：**真实本地 provider vs mock**。
        // 它证明的不是「本地更好」，而是**mock 不能当对照组** ——
        // 伪向量排出来的顺序没有产品含义，拿它做基线会让任何配置都看起来在进步。
        let mock = MockEmbeddingProvider(dimension: 64)
        let arms = [
            RetrievalExperiment.Arm(label: "local · \(local.modelInfo.version)",
                                    config: config("local", strategy: .block, provider: local)) {
                try await environment(strategy: .block, provider: local)
            },
            RetrievalExperiment.Arm(label: "mock（伪向量，仅作反例）",
                                    config: config("mock", strategy: .block, provider: mock)) {
                try await environment(strategy: .block, provider: mock)
            }
        ]

        guard let report = try? await RetrievalExperiment.run(title: "Embedding Provider",
                                                             cases: E.goldenSet(), arms: arms) else {
            r.expect(false, "实验应当跑完"); return
        }

        print("\n    ── 6.1 Embedding Provider 对比（\(buildMode) · \(E.notes.count) 篇笔记 / \(report.caseCount) 条 query）──")
        print(report.markdownTable().split(separator: "\n").map { "    " + $0 }.joined(separator: "\n"))

        let localArm = report.arms[0], mockArm = report.arms[1]
        r.expect(localArm.metrics.recallAt5 >= mockArm.metrics.recallAt5,
                 String(format: "真实 provider 不差于伪向量（%.3f vs %.3f）—— 若相反，说明这批用例靠字面就能命中，语义路没被测到",
                        localArm.metrics.recallAt5, mockArm.metrics.recallAt5))

        // Cloud 那一臂需要真实凭据。**没有凭据时不编数字**，明确标为待验证。
        let env = ProcessInfo.processInfo.environment
        guard let key = env["MOSAIC_LIVE_EMBEDDING_KEY"], !key.isEmpty,
              let base = env["MOSAIC_LIVE_EMBEDDING_BASE"], !base.isEmpty else {
            print("    Cloud 臂：**待验证** —— 需要 MOSAIC_LIVE_EMBEDDING_BASE / _KEY / _MODEL / _DIM 环境变量")
            print("    成本一项同样待验证：它由服务端计费口径决定，本地测不出来\n")
            r.expect(true, "无云端凭据时跳过，不编造质量 / 延迟 / 成本数字")
            return
        }
        let model = env["MOSAIC_LIVE_EMBEDDING_MODEL"] ?? "text-embedding-3-small"
        let dim = Int(env["MOSAIC_LIVE_EMBEDDING_DIM"] ?? "1536") ?? 1536
        let cloud = CloudEmbeddingProvider(baseURL: base, apiKey: key, model: model, dimension: dim)

        let cloudArm = RetrievalExperiment.Arm(label: "cloud · \(model)",
                                               config: config("cloud", strategy: .block, provider: cloud)) {
            try await environment(strategy: .block, provider: cloud)
        }
        guard let full = try? await RetrievalExperiment.run(title: "Embedding Provider（含云端）",
                                                           cases: E.goldenSet(),
                                                           arms: arms + [cloudArm]) else {
            r.expect(false, "云端实验失败 —— 凭据或网络问题，结论仍为待验证")
            return
        }
        print("\n" + full.markdownTable().split(separator: "\n").map { "    " + $0 }.joined(separator: "\n") + "\n")
        r.expect(full.arms.count == 3, "三臂对照完成")
        r.expect(full.arms[2].indexBuildMs > full.arms[0].indexBuildMs,
                 "云端建索引比本地慢 —— 这正是「质量之外的代价」那一列")
    }

    // MARK: 6.3 · 规模 benchmark 复测

    static func checkScaleBenchmark(_ r: CheckRunner) async {
        r.suite("Week6 · 6.3 规模 benchmark 复测 —— P95 曲线")

        #if DEBUG
        let sizes = [1_000, 5_000]
        let samples = 5
        #else
        let sizes = [1_000, 5_000, 20_000]
        let samples = 25
        #endif
        let dim = 384
        var rows: [(Int, Double, Double, Double)] = []

        for size in sizes {
            let store = InMemoryVectorStore()
            var chunks: [NoteChunk] = []
            chunks.reserveCapacity(size)
            for i in 0..<size {
                let ref = BlockRef(noteID: "n\(i / 20)", blockID: "b\(i)")
                let chunk = NoteChunk(id: "c\(i)", ref: ref, source: .text, indexInBlock: 0,
                                      text: "第 \(i) 段 排期 延期毕业 record \(i)", contentHash: "h\(i)")
                chunks.append(chunk)
                await store.upsert(EmbeddingRecord(ref: ref, chunkID: chunk.id, contentHash: chunk.contentHash,
                                                   embeddingVersion: "det-v1", dimension: dim,
                                                   vector: MockEmbeddingProvider.deterministicVector(for: chunk.id, dimension: dim)))
            }
            let service = RetrievalService(provider: MockEmbeddingProvider(dimension: dim), vectors: store)
            let cfg = RetrievalConfig(version: "scale", mode: .hybrid, embeddingProvider: "mock",
                                      embeddingVersion: "det-v1", chunkStrategy: .block, topK: 20)

            _ = await service.retrieve(query: "预热", chunks: chunks, config: cfg)
            var latencies: [Double] = []
            for i in 0..<samples {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = await service.retrieve(query: i % 2 == 0 ? "延期毕业" : "排期", chunks: chunks, config: cfg)
                latencies.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            }
            latencies.sort()
            rows.append((size,
                         latencies[latencies.count / 2],
                         latencies[min(latencies.count - 1, Int(Double(latencies.count) * 0.95))],
                         latencies.last ?? 0))
            r.expect(await store.count() == size, "\(size) 条向量入索引")
        }

        print("\n    ── 6.3 规模复测（\(buildMode) · dim \(dim) · hybrid 端到端，含 keyword 路）──")
        print("    chunks         P50         P95        max")
        for (size, p50, p95, mx) in rows {
            print(String(format: "    %6d   %8.2f ms %8.2f ms %8.2f ms", size, p50, p95, mx))
        }
        #if DEBUG
        print("    ⚠️ debug 构建（-Onone），不代表真实曲线。release 下重跑。")
        print("    ⚠️ 这是 Mac 数字。**iPhone 真机曲线待验证。**\n")
        r.expect(rows.count == sizes.count, "debug 下只测量不断言 SLO（D-RT-015）")
        #else
        print("    ⚠️ 这是 Mac 数字。**iPhone 真机曲线待验证。**\n")
        for (size, p50, p95, _) in rows {
            r.expect(p50 < 100, String(format: "%d chunks · P50 %.2f ms < 100 ms", size, p50))
            r.expect(p95 < 250, String(format: "%d chunks · P95 %.2f ms < 250 ms", size, p95))
        }
        r.expect(rows.last!.2 < 250,
                 "最大规模仍在 SLO 内 → Goal 1 不需要 ANN（D-RT-012 的结论在复测后仍成立）")
        #endif
    }

    // MARK: 6.4 · Staleness 实验

    /// 构造「改了内容但没重建索引」的场景，证明两件事：
    /// **一、过期结果不会被当成有效结果**；**二、检索层如实报告索引过期**。
    static func checkStalenessExperiment(_ r: CheckRunner) async {
        r.suite("Week6 · 6.4 Staleness 实验 —— 改内容不重建索引")

        let provider = MockEmbeddingProvider(dimension: 32)
        let store = InMemoryVectorStore()

        // 1 · 按旧内容建索引。
        let oldText = "周会上说排期结论是下周三交付"
        let oldBlock = RetrievalFoundationChecks.textBlock("B1", oldText, order: 0)
        let oldChunks = ChunkPipeline.chunks(noteID: "n1", blocks: [oldBlock], strategy: .block)
        for chunk in oldChunks {
            let v = try! await provider.embed(chunk.text)
            await store.upsert(EmbeddingRecord(ref: chunk.ref, chunkID: chunk.id, chunkIndex: chunk.indexInBlock,
                                               contentHash: chunk.contentHash, embeddingVersion: "mock-v1",
                                               dimension: v.count, vector: v))
        }
        let oldHash = oldChunks[0].contentHash

        // 2 · 内容被改。索引没动。
        let newText = "周会上说排期结论推迟到下个月"
        let newChunks = ChunkPipeline.chunks(noteID: "n1",
                                             blocks: [RetrievalFoundationChecks.textBlock("B1", newText, order: 0)],
                                             strategy: .block)
        r.expect(newChunks[0].contentHash != oldHash,
                 "改一个字 contentHash 就变 —— 过期检测的全部依据")
        r.expect(newChunks[0].id != oldChunks[0].id || newChunks[0].contentHash != oldHash,
                 "chunk 身份随内容变化")

        // 3 · 用新语料去查旧索引：向量命中的 chunkID 在当前语料里找不到，**被丢弃**，
        //     而不是拿旧文本当结果返回。
        let service = RetrievalService(provider: provider, vectors: store)
        let cfg = RetrievalConfig(version: "stale-exp", mode: .vector, embeddingProvider: "mock",
                                  embeddingVersion: "mock-v1", chunkStrategy: .block, topK: 10)
        let outcome = await service.retrieve(query: "排期结论", chunks: newChunks, config: cfg)
        r.expect(!outcome.results.contains { $0.text == oldText },
                 "过期向量对应的旧文本**不会**作为结果返回 —— 否则用户会搜到一段已经不存在的内容")

        // 4 · 写入路径：StaleGuard 拒收基于旧 hash 的结果。这是「不靠取消」的那一层 ——
        //     即使 provider 忽略取消、把旧内容的向量算完了，它也进不了 store。
        let staleResult = DerivedResult(key: EmbeddingJobKey(ref: oldChunks[0].ref,
                                                             contentHash: oldHash,
                                                             embeddingVersion: "mock-v1"),
                                        payload: [Float](repeating: 0, count: 32))
        let contextAfterEdit = DerivedWriteContext(noteExists: true,
                                                   currentContentHash: newChunks[0].contentHash,
                                                   currentEmbeddingVersion: "mock-v1")
        r.expect(!StaleGuard.decide(for: staleResult, context: contextAfterEdit).isAccepted,
                 "内容已变时 StaleGuard 拒收旧结果 —— 校验在写入路径上，绕不过去")
        let freshResult = DerivedResult(key: EmbeddingJobKey(ref: newChunks[0].ref,
                                                             contentHash: newChunks[0].contentHash,
                                                             embeddingVersion: "mock-v1"),
                                        payload: [Float](repeating: 0, count: 32))
        r.expect(StaleGuard.decide(for: freshResult, context: contextAfterEdit).isAccepted,
                 "内容未变时照常接受")

        // 5 · 索引状态如实推导，且 keyword 路在任何状态下都可用（I3）。
        let hybrid = RetrievalConfig(version: "stale-exp", mode: .hybrid, embeddingProvider: "mock",
                                     embeddingVersion: "mock-v1", chunkStrategy: .block, topK: 10)
        let stale = IndexStateMachine.derive(totalChunks: 1, pendingChunks: 1, runningJobs: 0,
                                             hasEmbeddings: true, failure: nil)
        r.expect(stale == .stale(pending: 1), "有待办且没有在跑的任务 → stale（\(stale.description)）")
        // **`stale` 仍然允许向量路**（`IndexState.allowsVectorRetrieval` 的注释）：
        // 部分现行的索引比没有索引有用，而它返回的每一条都要经过 chunkID 还原 ——
        // 还原不到就丢弃。这个实验证明的正是「丢弃真的发生了」，
        // 而不是「过期时干脆不查」。
        let onStale = await service.retrieve(query: "排期结论", chunks: newChunks,
                                             config: hybrid, indexState: stale)
        r.expect(!onStale.results.isEmpty, "索引过期时仍然有结果（keyword 路照常）")
        r.expect(!onStale.results.contains { $0.text == oldText },
                 "但过期向量指向的旧文本被丢弃 —— 不污染结果")

        // 无法推进时（provider 挂了 / 还没建起来）才整条降级为 keyword。
        let failed = IndexStateMachine.derive(totalChunks: 1, pendingChunks: 1, runningJobs: 0,
                                              hasEmbeddings: true, failure: "provider 不可用")
        r.expect(!failed.allowsVectorRetrieval, "failed 时不用向量路（\(failed.description)）")
        let degraded = await service.retrieve(query: "排期结论", chunks: newChunks,
                                              config: hybrid, indexState: failed)
        r.expect(!degraded.results.isEmpty, "降级后 keyword 路照常返回结果（I3）")
        r.expect(degraded.trace.isStale, "trace 如实标记这次检索没有用上向量路")
        r.expect(degraded.results.allSatisfy { $0.vectorRank == nil },
                 "降级时向量路整条跳过，不是「部分参与」")
    }

    // MARK: 6.5 · Regression 长跑 —— 新配置引入 regression → Gate 拦截

    /// backlog 6.5 要的是**一次完整记录**：失败 → 归因 → 进回归集 → 下一次评测
    /// 自动带上 → Pass Rate 掉到阈值以下 → Gate 拦住 → Promote 失败。
    static func checkRegressionBlocksRelease(_ r: CheckRunner) async {
        r.suite("Week6 · 6.5 Regression 长跑 —— 新配置引入回归，Gate 拦住")

        guard let provider = try? LocalEmbedding.make() else {
            r.expect(true, "本机无本地句向量模型，跳过（结论：待验证）")
            return
        }
        guard let (service, baseConfig) = await E.makeService() else {
            r.expect(false, "构建检索服务"); return
        }
        let runner = EvalRunner(service: service, chunksProvider: { E.chunks() })

        // ① 一次评测出现失败用例。
        guard let first = try? await runner.run(cases: E.goldenSet(), config: baseConfig),
              var failure = first.failures.first else {
            r.expect(false, "应当至少有一条失败用例"); return
        }
        r.expect(!failure.isTriaged, "新失败默认未归因")

        // ② 归因 → 进回归集。
        failure.failureType = .missingData
        failure.diagnosisNote = "语料里根本没有这段文本"
        var dataset = EvalDataset(golden: E.goldenSet())
        r.expect(dataset.addRegression(failure), "失败用例进入回归集")
        let combined = dataset.cases(.both)
        r.expect(combined.count == E.goldenSet().count + 1, "下一次评测自动带上回归集")

        // ③ 用**一套明显更差的配置**跑 —— keyword-only，语义路整条不参与。
        //    这就是「新配置引入 regression」的可复现形态。
        let candidateVersion = "retrieval-v2-keyword-only"
        let degraded = RetrievalConfig(version: candidateVersion, mode: .keyword,
                                       embeddingProvider: provider.modelInfo.identifier,
                                       embeddingVersion: provider.modelInfo.version,
                                       chunkStrategy: .block, topK: 10)
        guard let candidateRun = try? await runner.run(cases: combined, config: degraded),
              let baselineRun = try? await runner.run(cases: combined,
                                                      config: RetrievalConfig(version: candidateVersion,
                                                                              mode: .hybrid,
                                                                              embeddingProvider: provider.modelInfo.identifier,
                                                                              embeddingVersion: provider.modelInfo.version,
                                                                              chunkStrategy: .block, topK: 10)) else {
            r.expect(false, "两次跑批应当成功"); return
        }

        print("\n    ── 6.5 Regression 长跑（\(buildMode) · \(combined.count) 条用例）──")
        print(String(format: "    baseline(hybrid)  Recall@5 = %.3f  MRR = %.3f  Regression = %.3f",
                     baselineRun.metrics.recallAt5, baselineRun.metrics.mrr, baselineRun.regressionPassRate))
        print(String(format: "    candidate(keyword) Recall@5 = %.3f  MRR = %.3f  Regression = %.3f",
                     candidateRun.metrics.recallAt5, candidateRun.metrics.mrr, candidateRun.regressionPassRate))

        r.expect(candidateRun.regressionMetrics.caseCount == 1, "回归部分单独统计")
        r.expect(candidateRun.regressionPassRate == candidateRun.regressionMetrics.recallAt5,
                 "Pass Rate 与 Recall@5 同口径")

        // ④ Gate 判定。
        // 分层 policy 之后判定需要测量环境；这一节测的是 regression 拦截，
        // 所以给一个与当前构建匹配的合格环境。
        let benchEnv = RunEnvironment(deviceClass: .mac, deviceModel: "test", osVersion: "test",
                                      buildConfiguration: buildMode, thermalState: "nominal",
                                      lowPowerMode: false, measuredLayer: .firstResult)
        let decision = ReleaseGate.evaluate(
            configVersion: candidateVersion, current: candidateRun, baseline: baselineRun,
            thresholds: GateThresholds(performance: PerformanceGatePolicy(
                version: "test-perf", firstResultP50Ms: 1_000, firstResultP95Ms: 1_000,
                requiredDeviceClass: .mac, requiredBuildConfiguration: buildMode)),
            environment: benchEnv)
        print("    Gate → \(decision.headline)：\(decision.blockingReasons.joined(separator: "；"))\n")
        r.expect(decision.status == .blocked,
                 "回归用例挂了（Pass Rate \(String(format: "%.3f", candidateRun.regressionPassRate)) < 0.98）→ Gate 拦住")
        r.expect(decision.blockingChecks.contains { $0.kind == .regression },
                 "阻断原因里包含 Regression 那一项")
        r.expect(decision.blockingChecks.first { $0.kind == .regression }?.opensFailures == true,
                 "阻断行直达 D9 —— 从「不能上线」到「为什么」一次点击")

        // ⑤ Promote 被拒。
        var registry = RetrievalConfigRegistry()
        let productionMode = registry.production.config.mode
        // 候选必须与生产**不同**，否则「没有被换掉」这条断言在两者相同时恒成立，
        // 也就什么都保护不了。生产是 keyword，那候选就取 hybrid。
        let candidate = try! registry.duplicate(from: registry.production.id) { $0.mode = .hybrid }
        try! registry.setCandidate(id: candidate.id)
        var promoteFailed = false
        do { _ = try registry.promote(id: candidate.id, decision: decision) } catch { promoteFailed = true }
        r.expect(promoteFailed, "BLOCKED 的判定无法 promote —— 完整闭环到此成立")
        r.expect(registry.production.config.mode == productionMode && productionMode == .keyword,
                 "生产配置仍是 keyword，没有被换成候选的 hybrid")
    }

    // MARK: 6.6 · 无障碍朗读顺序

    static func checkAccessibilityReadingOrder(_ r: CheckRunner) {
        r.suite("Week6 · 6.6 结果行朗读顺序 —— 标题 → 来源 → 命中片段 → 文件夹 → 时间")

        let row = NoteSearchResult(
            noteID: "n1", rank: 1, anchor: .transcript("b1"), source: .transcript,
            excerpt: Excerpt(text: "录音里提到延期毕业的流程", highlights: [TextRange(start: 6, end: 10)]))
        let label = SearchPresentation.accessibilityLabel(row: row, title: "周会录音",
                                                          folderName: "学业", relativeTime: "昨天")
        let parts = label.components(separatedBy: "，")
        r.expect(parts.count == 5, "五个槽位都朗读（\(label)）")
        r.expect(parts[0] == "周会录音", "① 标题")
        r.expect(parts[1] == "来自录音转写", "② 来源 —— 视觉上它只是个 20pt 图标，读屏用户拿不到这条线索")
        r.expect(parts[2].contains("延期毕业"), "③ 命中片段")
        r.expect(parts[3] == "学业", "④ 文件夹")
        r.expect(parts[4] == "昨天", "⑤ 时间")
        r.expect(!label.contains("命中") && !label.contains("高亮"),
                 "高亮区间不进入朗读 —— 对比式前景高亮是视觉手段，读出来只会打断句子")

        // 纯文本命中没有来源标签：它是默认形态，读出「文字」只是噪声。
        let plain = NoteSearchResult(noteID: "n2", rank: 2, anchor: .block("b2"), source: .text,
                                     excerpt: Excerpt(text: "排期结论：下周三", highlights: []))
        let plainLabel = SearchPresentation.accessibilityLabel(row: plain, title: "会议记录",
                                                               folderName: nil, relativeTime: "3 天前")
        r.expect(plainLabel.components(separatedBy: "，").count == 3,
                 "无来源、无文件夹时只读三段（\(plainLabel)）")
        r.expect(SearchPresentation.sourceLabel(.text) == nil, "纯文本没有来源标签")

        // 用户侧禁用词表（§1.1.1）在朗读文本里同样适用。
        let banned = ["embedding", "向量", "余弦", "RRF", "融合", "chunk", "分块",
                      "Recall", "index", "rerank", "top-k", "语义检索", "semantic",
                      "contentHash", "stale"]
        for source in RetrievalSource.allCases {
            guard let text = SearchPresentation.sourceLabel(source) else { continue }
            r.expect(!banned.contains { text.lowercased().contains($0.lowercased()) },
                     "来源朗读文案不含技术词：\(text)")
        }
    }

    static func run(_ r: CheckRunner) async {
        await checkHybridVsKeywordBaseline(r)
        await checkChunkStrategyExperiment(r)
        await checkCosineLengthBias(r)
        await checkLocalVsCloudExperiment(r)
        await checkScaleBenchmark(r)
        await checkStalenessExperiment(r)
        await checkRegressionBlocksRelease(r)
        checkAccessibilityReadingOrder(r)
    }
}
