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

    static func cloudProvider() -> (any EmbeddingProvider)? {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["MOSAIC_LIVE_EMBEDDING_BASE"], !base.isEmpty,
              let key = env["MOSAIC_LIVE_EMBEDDING_KEY"], !key.isEmpty else { return nil }
        let model = env["MOSAIC_LIVE_EMBEDDING_MODEL"] ?? "BAAI/bge-m3"
        let dim = Int(env["MOSAIC_LIVE_EMBEDDING_DIM"] ?? "1024") ?? 1024
        return CloudEmbeddingProvider(baseURL: base, apiKey: key, model: model, dimension: dim)
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

        var cloudBuild: (ms: Double, chars: Int)? = nil
        if let cloud = cloudProvider() {
            do {
                let built = try await buildIndex(chunks, provider: cloud)
                cloudBuild = (built.ms, built.chars)
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
        if let cloudBuild {
            print(String(format: "\n    云端建索引 measured: %d chunks / %d 字符 / %.0f ms（%.1f ms per chunk）",
                         chunks.count, cloudBuild.chars, cloudBuild.ms, cloudBuild.ms / Double(chunks.count)))
            print("    ⚠️ 20k chunk 的耗时是 linear extrapolation，**不是 measured**，不得当正式 benchmark")
        } else {
            print("\n    ⚠️ 云端两路：**待验证**（需要 MOSAIC_LIVE_EMBEDDING_BASE / _KEY / _MODEL / _DIM）")
        }
        print("")

        // ── 断言：口径与不变量，**不断言具体质量数字** ──
        r.expect(results.contains { $0.arm == "keyword" }, "keyword baseline 必须在对照里")
        r.expect(results.allSatisfy { $0.metrics.recallAt1 <= $0.metrics.recallAt3 + 1e-9 },
                 "R@1 ≤ R@3（单调）")
        r.expect(results.allSatisfy { $0.metrics.recallAt3 <= $0.metrics.recallAt5 + 1e-9 },
                 "R@3 ≤ R@5（单调）")
        r.expect(negativeRows.first { $0.0 == "keyword" }?.1.noResultAccuracy == 1.0,
                 "keyword 对无答案 query 返回空 —— 它是 no-result 的唯一现有保障")

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
        // Gate 只读 in-scope（§B），四项 allSatisfy。这里跑的是**真实**判定，
        // 不是手算 —— 结论好不好看都要照报。
        if let candidate = metric("cloud-hybrid", "in-scope"),
           let baseline = metric("local-hybrid", "in-scope") {
            func run(_ m: EvalMetrics, _ version: String) -> EvalRun {
                EvalRun(configVersion: version, embeddingVersion: version,
                        metrics: m, goldenMetrics: m, regressionMetrics: .zero,
                        failures: [], inScopeMetrics: m)
            }
            let decision = ReleaseGate.evaluate(configVersion: "cloud-hybrid-v1",
                                                current: run(candidate, "cloud-hybrid-v1"),
                                                baseline: run(baseline, "cloud-hybrid-v1"))
            print("\n    ── Release Gate（candidate = cloud-hybrid · baseline = local-hybrid · 只看 in-scope）──")
            print("    判定：\(decision.headline)")
            for c in decision.checks {
                print(String(format: "      %@ %-12@ %-22@ 要求 %@", c.passed ? "✅" : "❌",
                             c.kind.label as NSString, c.actualText as NSString, c.conditionText))
            }
            r.expect(decision.checks.count == 4, "Gate 四项检查全部产出")
            let p95Check = decision.checks.first { $0.kind == .p95 }
            r.expect(p95Check?.passed == false,
                     "云端 P95 超 250ms 预算 → Gate 阻断。**质量再好也不能靠加权换放行**（D-UI-DEV-008）")
            r.expect(decision.status == .blocked,
                     "cloud-hybrid 当前**不能**进生产：质量三项全过，P95 一项否决")
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
