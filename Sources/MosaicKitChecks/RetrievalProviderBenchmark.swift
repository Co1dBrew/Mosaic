import Foundation
import MosaicKit

/// # 五路 Provider 对照（D-AI-003 的证据）
///
/// **产品上线的是 Hybrid，不是 raw vector**，所以只比 local embedding vs cloud
/// embedding 是不够的。这里比五路：
///
/// ```
/// Keyword · Local Vector · Cloud Vector · Local Hybrid · Cloud Hybrid
/// ```
///
/// ## 主指标换成 R@1 / MRR
///
/// v2 上 Cloud 的 R@5 已经打到 1.000 —— 那不是「检索完美」，是**评测集到了天花板**。
/// R@5 降级为 safety-net metric，判定看 **R@1 与 MRR**（`HUMANLIKE_GOLDEN_SET.md`）。
///
/// ## 云端臂要凭据
///
/// 没有 `MOSAIC_LIVE_EMBEDDING_*` 时只跑本地三路，并明确打印「云端待验证」——
/// 不编造，也不因为缺凭据就让整套 checks 变红。
enum RetrievalProviderBenchmark {

    struct Arm {
        let name: String
        let mode: RetrievalMode
        let provider: (any EmbeddingProvider)?
        let store: InMemoryVectorStore
    }

    struct GroupResult {
        let arm: String
        let group: String
        let metrics: EvalMetrics
    }

    static func cloudProvider(latency: EmbeddingLatencyRecorder? = nil) -> (any EmbeddingProvider)? {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["MOSAIC_LIVE_EMBEDDING_BASE"], !base.isEmpty,
              let key = env["MOSAIC_LIVE_EMBEDDING_KEY"], !key.isEmpty else { return nil }
        let model = env["MOSAIC_LIVE_EMBEDDING_MODEL"] ?? "BAAI/bge-m3"
        let dim = Int(env["MOSAIC_LIVE_EMBEDDING_DIM"] ?? "1024") ?? 1024
        return CloudEmbeddingProvider(baseURL: base, apiKey: key, model: model, dimension: dim,
                                      latency: latency)
    }

    /// 云端服务的区域标签。**延迟是地理量**，不带 region 的云端延迟数字不可比，
    /// 所以它跟着跑批一起进 `RunEnvironment`，而不是写在文档的脚注里。
    static var cloudRegion: String? {
        let raw = ProcessInfo.processInfo.environment["MOSAIC_LIVE_EMBEDDING_REGION"]
        return (raw?.isEmpty == false) ? raw : nil
    }

    /// 批量建索引。**批量不是优化，是成本要求** —— 云端按请求计费。
    static func buildIndex(_ chunks: [NoteChunk], provider: any EmbeddingProvider,
                           batch: Int = 32) async throws -> (store: InMemoryVectorStore, ms: Double, chars: Int) {
        let store = InMemoryVectorStore()
        var chars = 0
        let t0 = DispatchTime.now().uptimeNanoseconds
        for start in stride(from: 0, to: chunks.count, by: batch) {
            let slice = Array(chunks[start..<min(start + batch, chunks.count)])
            let vectors = try await provider.embed(batch: slice.map(\.text))
            chars += slice.reduce(0) { $0 + $1.text.count }
            for (chunk, vector) in zip(slice, vectors) {
                await store.upsert(EmbeddingRecord(ref: chunk.ref, chunkID: chunk.id,
                                                   chunkIndex: chunk.indexInBlock,
                                                   contentHash: chunk.contentHash,
                                                   embeddingVersion: provider.modelInfo.version,
                                                   chunkStrategy: chunk.strategy,
                                                   dimension: vector.count, vector: vector))
            }
        }
        return (store, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000, chars)
    }

    static func run(_ r: CheckRunner) async {
        r.suite("D-AI-003 · 五路 Provider 对照（Keyword / Local / Cloud × Vector / Hybrid）")

        guard let dataset = try? HumanLikeGoldenFixture.load() else {
            r.expect(false, "fixture 应当可加载"); return
        }
        let chunks = dataset.chunks
        let cases = dataset.evalCases
        let negatives = dataset.negativeEvalCases

        guard let local = try? LocalEmbedding.make() else {
            r.expect(true, "本机没有中文句向量模型，跳过 provider 对照；结构检查仍有效")
            return
        }
        guard let localIndex = try? await buildIndex(chunks, provider: local) else {
            r.expect(false, "本地索引应当可建"); return
        }

        var arms: [Arm] = [
            Arm(name: "keyword", mode: .keyword, provider: nil, store: InMemoryVectorStore()),
            Arm(name: "local-vector", mode: .vector, provider: local, store: localIndex.store),
            Arm(name: "local-hybrid", mode: .hybrid, provider: local, store: localIndex.store)
        ]

        // 云端建索引的耗时与 token 都要采下来 —— backlog 6.1 的三项里，
        // **成本**一直是空的（「本地测不出来」），缺的就是服务端回报的 token 数。
        let cloudLatency = EmbeddingLatencyRecorder()
        var cloudBuild: (ms: Double, chars: Int, tokens: Int, unreported: Int)? = nil
        if let cloud = cloudProvider(latency: cloudLatency) {
            do {
                let built = try await buildIndex(chunks, provider: cloud)
                // **建索引之后、跑批之前**读 token —— 跑批的 query embedding 也走同一个
                // recorder，混进来就不再是「索引一次要多少钱」了。
                let usage = await cloudLatency.promptTokenTotal()
                cloudBuild = (built.ms, built.chars, usage.tokens, usage.unreportedCalls)
                arms += [
                    Arm(name: "cloud-vector", mode: .vector, provider: cloud, store: built.store),
                    Arm(name: "cloud-hybrid", mode: .hybrid, provider: cloud, store: built.store)
                ]
            } catch {
                r.expect(true, "云端索引失败（\(error)）—— 云端臂标为待验证，本地三路照常")
            }
        }

        var results: [GroupResult] = []
        var negativeRows: [(String, EvalMetrics)] = []
        for arm in arms {
            let service = RetrievalService(provider: arm.provider, vectors: arm.store)
            let config = RetrievalConfig(version: "bench-\(arm.name)", mode: arm.mode,
                                         embeddingProvider: arm.provider?.modelInfo.identifier ?? "none",
                                         embeddingVersion: arm.provider?.modelInfo.version ?? "none",
                                         chunkStrategy: .default, topK: 10)
            let runner = EvalRunner(service: service, chunksProvider: { chunks })
            guard let run = try? await runner.run(cases: cases, config: config),
                  let negRun = try? await runner.run(cases: negatives, config: config) else {
                r.expect(false, "\(arm.name) 跑批失败"); continue
            }
            results += [GroupResult(arm: arm.name, group: "in-scope", metrics: run.inScopeMetrics),
                        GroupResult(arm: arm.name, group: "cross", metrics: run.crossLanguageMetrics),
                        GroupResult(arm: arm.name, group: "overall", metrics: run.metrics)]
            negativeRows.append((arm.name, negRun.metrics))
        }

        print("\n    ── D-AI-003 五路对照（\(dataset.notes.count) notes / \(cases.count) queries · \(buildMode)）──")
        print("    主指标是 R@1 / MRR；R@5 已在 v2 饱和，降级为 safety-net")
        print("    arm           group       R@1     R@3     R@5     MRR      P50      P95")
        for row in results {
            print(String(format: "    %-13@ %-10@  %.3f   %.3f   %.3f   %.3f  %7.2fms %7.2fms",
                         row.arm as NSString, row.group as NSString,
                         row.metrics.recallAt1, row.metrics.recallAt3, row.metrics.recallAt5,
                         row.metrics.mrr, row.metrics.p50Ms, row.metrics.p95Ms))
        }
        print("\n    负例（no-result accuracy / false-positive rate）")
        for (arm, m) in negativeRows {
            print(String(format: "    %-13@ %6.1f%%          %6.1f%%", arm as NSString,
                         m.noResultAccuracy * 100, m.falsePositiveRate * 100))
        }
        // ── 成本对照（backlog 6.1 的第三项）──
        //
        // 质量与延迟一直有数，**成本一栏是空的**。空在哪很具体：本地那一路的
        // 「代价」是墙上时间和电，云端那一路的代价是 token 和钱，两者没有共同单位。
        // 所以这里不合成一个「成本分」，而是把两种代价并排摆出来，各自标口径。
        print("\n    ── 成本对照（同一份语料 \(chunks.count) chunks / \(localIndex.chars) 字符）──")
        print(String(format: "    local  · %@  建索引 %.0f ms（%.1f ms per chunk）· 计费 0 —— 代价是设备时间与电",
                     local.modelInfo.identifier as NSString,
                     localIndex.ms, localIndex.ms / Double(chunks.count)))
        if let cloudBuild {
            print(String(format: "    cloud  · 建索引 %.0f ms（%.1f ms per chunk）· prompt_tokens %d（服务端回报，measured）",
                         cloudBuild.ms, cloudBuild.ms / Double(chunks.count), cloudBuild.tokens))
            if cloudBuild.tokens > 0 {
                print(String(format: "             %.2f token/字符 · %.1f token/chunk —— 换算率**实测**，不再用 3.7 字符/token 外推",
                             Double(cloudBuild.tokens) / Double(max(cloudBuild.chars, 1)),
                             Double(cloudBuild.tokens) / Double(chunks.count)))
            }
            if cloudBuild.unreported > 0 {
                print("             ⚠️ 有 \(cloudBuild.unreported) 次调用服务端没回报 usage —— token 合计是下限，不是全量")
            }
            print(String(format: "    倍率   · 本次云端建索引比本地慢 %.1f 倍 —— ⚠️ **这个倍率不稳定**，",
                         cloudBuild.ms / max(localIndex.ms, 0.001)))
            print("             同一份语料多次跑批的单 chunk 耗时落在 24–345 ms，差 **14 倍**。")
            print("             云端建索引是网络量，**不是算力量**：本地那一侧 16–19 ms/chunk 稳定，")
            print("             变的全在网络。要引用就引 token（每次都一样），不要引墙上时间。")
            print("    ⚠️ 20k chunk 的耗时与 token 都是 linear extrapolation，**不是 measured**，不得当正式 benchmark")
        } else {
            print("    cloud  · **待验证**（需要 MOSAIC_LIVE_EMBEDDING_BASE / _KEY / _MODEL / _DIM）")
        }
        print("")

        // ── 断言：口径与不变量，**不断言具体质量数字** ──
        r.expect(results.contains { $0.arm == "keyword" }, "keyword baseline 必须在对照里")
        r.expect(results.allSatisfy { $0.metrics.recallAt1 <= $0.metrics.recallAt3 + 1e-9 },
                 "R@1 ≤ R@3（单调）")
        r.expect(results.allSatisfy { $0.metrics.recallAt3 <= $0.metrics.recallAt5 + 1e-9 },
                 "R@3 ≤ R@5（单调）")
        // ── 这条断言的**阈值**在 v5 被修正过，理由必须写清楚 ──
        //
        // 原文要求 keyword 对无答案 query 的正确率**恰好 100%**，并称它是
        // no-result 的唯一保障。100% 这个水平其实是 CJK 分词缺陷的**副产品**：
        // 一个从不匹配中文自然句的词法路，对中文无答案 query 当然永远返回空。
        // 换句话说，它测到的不是「系统会克制」，而是「系统查不动中文」。
        //
        // 修好切分之后（`QuerySegmentation`），中文 query 真的会去匹配语料，
        // 于是少数无答案 query 也会撞上一些相邻字对。development 上实测
        // 100% → 90%，换来 in-scope R@1 **+67%**（0.175 → 0.292）。
        //
        // 阈值取 **0.85**：保留「keyword 路显著克制」这个可证伪的主张，
        // 同时不再把一个缺陷的副产品当成质量标准。
        // 真正解决误报要靠相关性下限（TD-10，abstention 目前 EXPERIMENT_ONLY），
        // 不是靠一个查不动中文的分词器。
        let keywordNoResult = negativeRows.first { $0.0 == "keyword" }?.1.noResultAccuracy ?? 0
        r.expect(keywordNoResult >= 0.85,
                 String(format: "keyword 对无答案 query 的克制率 %.0f%% ≥ 85%%（它仍是 no-result 的主要保障）",
                        keywordNoResult * 100))

        func metric(_ arm: String, _ group: String) -> EvalMetrics? {
            results.first { $0.arm == arm && $0.group == group }?.metrics
        }
        if let lh = metric("local-hybrid", "cross"), let ch = metric("cloud-hybrid", "cross") {
            r.expect(ch.recallAt5 > lh.recallAt5,
                     String(format: "云端 Hybrid 的 cross-language R@5 高于本地（%.3f > %.3f）—— D-AI-003 的核心证据",
                            ch.recallAt5, lh.recallAt5))
        }
        // ── Release Gate 判定：cloud-hybrid 作为候选，local-hybrid 作为 baseline ──
        //
        // Gate 只读 in-scope（§B）。这里跑的是**真实**判定，不是手算 ——
        // 结论好不好看都要照报。
        //
        // **这一段在分层 SLO（perf-v2）落地后改过口径。** 旧版断言的是
        // 「四项产出 · P95 一项否决 · blocked」，那是 perf-v1 用**一个** 250 ms
        // 判所有层时的结论。perf-v2 之后两件事同时变了：
        //
        // 1. 云端语义是 Metric B-cloud，policy 明确「记录但不判定」——
        //    再拿 250 ms 去否决它，等于把一次跨洲网络往返和一次本机余弦当成同一件事。
        // 2. 这批数字跑在 Mac 上，**根本没有资格参与判定** → STALE。
        //
        // 所以现在断言的是 STALE，而不是 blocked。**这不是把红灯改绿**：
        // 判定更严了 —— 以前 Mac 数字还能进 Gate 挨一顿判，现在直接不予受理。
        if let candidate = metric("cloud-hybrid", "in-scope"),
           let baseline = metric("local-hybrid", "in-scope") {
            func run(_ m: EvalMetrics, _ version: String) -> EvalRun {
                EvalRun(configVersion: version, embeddingVersion: version,
                        metrics: m, goldenMetrics: m, regressionMetrics: .zero,
                        failures: [], inScopeMetrics: m)
            }
            // 真实环境，**不伪造**：这台机器、这个构建、这一层、这个区域。
            let actual = RunEnvironment.capture(layer: .semanticCloud, providerRegion: cloudRegion)
            let decision = ReleaseGate.evaluate(configVersion: "cloud-hybrid-v1",
                                                current: run(candidate, "cloud-hybrid-v1"),
                                                baseline: run(baseline, "cloud-hybrid-v1"),
                                                thresholds: GateThresholds(performance: .v2),
                                                environment: actual)
            print("\n    ── Release Gate（candidate = cloud-hybrid · baseline = local-hybrid · 只看 in-scope）──")
            print("    环境：\(actual.deviceClass.rawValue) / \(actual.buildConfiguration) / "
                  + "layer \(actual.measuredLayer.rawValue) / region \(actual.providerRegion ?? "未记录")")
            print("    perf-v2 判定：\(decision.headline)")
            for reason in decision.blockingReasons { print("      · \(reason)") }
            for c in decision.checks {
                print(String(format: "      %@ %-22@ %-26@ 要求 %@", c.passed ? "✅" : "❌",
                             c.kind.label as NSString, c.actualText as NSString, c.conditionText))
            }

            r.expect(decision.status == .stale,
                     "Mac 上跑出来的云端质量数字 **不予受理**（perf-v2 要求真机 release）—— "
                     + "Gate 在正常工作，不是失败")
            r.expect(decision.checks.isEmpty,
                     "STALE 时不列四项 —— 环境不合格时那些数字没有解释意义")

            // 同一份数字换 perf-v1（单一 250 ms、允许 Mac）→ 才会真正判四项。
            // 保留它是为了**对照**：D-UI-DEV-008 的「质量再好也不能靠加权换放行」
            // 是在这个口径下被证明的，不能因为换了 policy 就当没发生过。
            let underV1 = ReleaseGate.evaluate(configVersion: "cloud-hybrid-v1",
                                               current: run(candidate, "cloud-hybrid-v1"),
                                               baseline: run(baseline, "cloud-hybrid-v1"),
                                               thresholds: GateThresholds(performance: .v1),
                                               environment: actual)
            print("    perf-v1 判定（单一 250ms · 允许 Mac）：\(underV1.headline)")
            for c in underV1.checks {
                print(String(format: "      %@ %-22@ %-26@ 要求 %@", c.passed ? "✅" : "❌",
                             c.kind.label as NSString, c.actualText as NSString, c.conditionText))
            }
            if underV1.status == .stale {
                // debug 构建下 perf-v1 同样不予受理（它只放宽机型，不放宽构建配置）。
                r.expect(buildMode == "debug",
                         "perf-v1 判 STALE 只该发生在 debug 构建（实际 \(buildMode)）")
            } else {
                r.expect(underV1.checks.count == 4, "perf-v1 下四项检查全部产出")
                let latency = underV1.checks.first { $0.kind == .semanticLatency }
                r.expect(latency?.passed == false,
                         "perf-v1 下云端语义 P95 超 250ms → 阻断。"
                         + "**质量再好也不能靠加权换放行**（D-UI-DEV-008）")
                r.expect(underV1.status == .blocked,
                         "perf-v1 下 cloud-hybrid 被延迟一项否决 —— 质量三项全过也不放行")
            }

            // **现在挡住云端上线的到底是什么** —— 这一句必须写清楚，
            // 否则「以前是延迟挡的」会被当成现在仍然如此。
            print("    ↳ perf-v2 下延迟不再是否决项（Metric B-cloud 记录不判定）；"
                  + "当前的阻断来自**测量环境**，以及评测集仍是 synthetic。")
        }

        // RRF 是否仍有价值：Cloud Vector vs Cloud Hybrid
        if let cv = metric("cloud-vector", "overall"), let ch = metric("cloud-hybrid", "overall") {
            print(String(format: "    RRF 价值（overall）：vector R@1 %.3f MRR %.3f  →  hybrid R@1 %.3f MRR %.3f",
                         cv.recallAt1, cv.mrr, ch.recallAt1, ch.mrr))
            r.expect(true, String(format: "RRF 价值已量化（ΔR@1 %+.3f · ΔMRR %+.3f）—— 结论以实测为准，不为「PRD 写了 RRF」强行保留",
                                  ch.recallAt1 - cv.recallAt1, ch.mrr - cv.mrr))
        }
    }

    static var buildMode: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
}
