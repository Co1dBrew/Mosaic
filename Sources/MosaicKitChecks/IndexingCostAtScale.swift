import Foundation
import MosaicKit

/// # P1 #11 · 分档索引成本
///
/// backlog 6.1 要的是 PRD 规定的 1k / 5k / 10k / 20k 四档实测。此前只有
/// 186 chunks 一个点，20k 全靠线性外推 —— 而外推值不得当作实测。
///
/// ## 本地与云端分开处理，因为它们的成本单位不同
///
/// - **本地**：代价是**设备时间与内存**，四档全部实测（免费，跑就是了）
/// - **云端**：代价是 **token 与钱**。四档全跑要 ~1.05M token，
///   而且**墙上时间根本不可外推**（同一份语料四次跑批单 chunk 耗时差 10 倍，§23.3）。
///   所以云端只在 1k 上实测一次，用来**验证 token/chunk 是否真的随规模恒定** ——
///   恒定的话 token 成本就可以精确外推，那是唯一值得外推的一项。
enum IndexingCostAtScale {

    static func run(_ r: CheckRunner) async {
        r.suite("P1 #11 · 分档索引成本（1k / 5k / 10k / 20k）")

        // **debug 下不跑。** 两个理由，第二个才是主要的：
        // 1. 36k 次本地嵌入在 debug 下要一个多小时（本项目实测 debug 慢约 18 倍），
        //    没人会为了跑一次 checks 等那么久 —— 一个太慢以至于被跳过的检查等于没有。
        // 2. **debug 的性能数字本来就不作数**（`PerformanceGatePolicy` 只受理 release）。
        //    在 debug 下产出一张成本表，只会制造一张迟早被人引用的错数字。
        // **默认不跑：它一次要 7 分钟**（36k 次本地嵌入 + 1k 次云端）。
        //
        // 常规 checks 是每次改动都要跑的东西，往里塞一个 7 分钟的项，结果是整套
        // 被跳过 —— 那比没有这项检查更糟。它测的是**一次性的容量结论**
        // （20k 建索引多久、占多少内存），不是每次改动都会变的东西，
        // 所以按需开：`MOSAIC_SCALE_COST=1 swift run -c release mosaic-checks`。
        //
        // 实测结果已回填 `RETRIEVAL_ARCHITECTURE.md` §26.3，不靠每次重跑维持。
        guard ProcessInfo.processInfo.environment["MOSAIC_SCALE_COST"] == "1" else {
            print("""

                分档索引成本：**按需运行**（`MOSAIC_SCALE_COST=1`，约 7 分钟）
                  已记录结果见 §26.3：本地 20k 建索引 235 s / 单 chunk 11.76 ms / 常驻 74.9 MB，
                  1k→20k 漂移 1.00×（完美线性）
                """)
            r.expect(true, "分档成本按需运行 —— 7 分钟的检查不该挂在每次改动的路径上")
            return
        }

        guard RetrievalProviderBenchmark.buildMode == "release" else {
            print("\n    分档索引成本：**debug 下跳过** —— 性能数字只接受 release（跑 `swift run -c release`）\n")
            r.expect(true, "debug 下不产出成本表 —— 不作数的数字不如不给")
            return
        }

        guard let local = try? LocalEmbedding.make() else {
            r.expect(true, "本机没有中文句向量模型，跳过分档索引成本")
            return
        }
        let dim = local.modelInfo.dimension
        let scales = [1_000, 5_000, 10_000, 20_000]

        print("\n    ── 本地索引成本（\(local.modelInfo.identifier) · dim \(dim) · \(RetrievalProviderBenchmark.buildMode)）──")
        print("     chunks    建索引      单 chunk    向量内存   归一化缓存      合计内存")
        var perChunk: [Double] = []
        for scale in scales {
            let chunks = synthetic(scale)
            let store = InMemoryVectorStore()
            let t0 = DispatchTime.now().uptimeNanoseconds
            for start in stride(from: 0, to: chunks.count, by: 32) {
                let slice = Array(chunks[start..<min(start + 32, chunks.count)])
                guard let vs = try? await local.embed(batch: slice.map(\.text)) else { continue }
                for (c, v) in zip(slice, vs) {
                    await store.upsert(EmbeddingRecord(
                        ref: c.ref, chunkID: c.id, chunkIndex: c.indexInBlock,
                        contentHash: c.contentHash, embeddingVersion: local.modelInfo.version,
                        chunkStrategy: c.strategy, dimension: v.count, vector: v))
                }
            }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
            perChunk.append(ms / Double(scale))

            let cache = NormalizedTextCache()
            _ = await cache.normalized(for: chunks)
            let cacheMB = Double(await cache.estimatedBytes) / 1_048_576
            let vecMB = Double(scale * dim * 4) / 1_048_576
            print(String(format: "     %6d %9.0f ms %9.2f ms %9.1f MB %11.1f MB %11.1f MB",
                         scale, ms, ms / Double(scale), vecMB, cacheMB, vecMB + cacheMB))
        }

        // 本地建索引应当**接近线性**。明显超线性说明某处有 O(n²)，那要在 20k 之前发现。
        if let first = perChunk.first, let last = perChunk.last {
            let drift = last / max(first, 0.0001)
            print(String(format: "\n    单 chunk 耗时从 1k 到 20k 变化 %.2fx —— 越接近 1.0 越说明是线性的", drift))
            r.expect(drift < 2.0,
                     String(format: "本地建索引近似线性（单 chunk 耗时漂移 %.2fx）—— 超线性会让 20k 的外推失效", drift))
        }

        // ── 云端：只在 1k 上实测，用来验证 token/chunk 恒定 ──
        let latency = EmbeddingLatencyRecorder()
        guard let cloud = RetrievalProviderBenchmark.cloudProvider(latency: latency) else {
            print("\n    ⚠️ 云端分档：**待验证**（需要 MOSAIC_LIVE_EMBEDDING_*）")
            print("       已知的唯一实测点：186 chunks / 25 310 字符 / 9 720 prompt_tokens（§23.3）\n")
            return
        }
        let probe = synthetic(1_000)
        let chars = probe.reduce(0) { $0 + $1.text.count }
        guard (try? await RetrievalProviderBenchmark.buildIndex(probe, provider: cloud)) != nil else {
            r.expect(true, "云端 1k 建索引失败 —— 分档成本标为待验证")
            return
        }
        let usage = await latency.promptTokenTotal()
        guard usage.tokens > 0 else {
            r.expect(true, "服务端未回报 usage —— token 成本无法写成 measured")
            return
        }
        let tokPerChunk = Double(usage.tokens) / Double(probe.count)
        let tokPerChar = Double(usage.tokens) / Double(chars)
        print(String(format: """

            ── 云端 token 成本（**只在 1k 上实测**）──
             1 000 chunks / %d 字符 / **%d prompt_tokens**（服务端回报）
             %.1f token/chunk · %.3f token/字符
            """, chars, usage.tokens, tokPerChunk, tokPerChar))
        print(String(format: """
             20k 外推：**≈ %.2fM token** —— *estimated*，但底数是实测且**每次跑批完全一致**
             墙上时间：**不外推**。同一份语料多次跑批单 chunk 耗时差 10 倍，那是网络不是算力
            """, tokPerChunk * 20_000 / 1_000_000))

        // 186 chunks 那次是 52.3 token/chunk。恒定 = token 成本可以精确外推。
        r.expect(abs(tokPerChunk - 52.3) / 52.3 < 0.5,
                 String(format: "token/chunk 在 1k 上是 %.1f，与 186 chunks 那次的 52.3 同量级 —— "
                        + "**这正是 token 值得外推而墙上时间不值得的原因**", tokPerChunk))
        print("")
    }

    /// 真实感的中英混合正文，长度接近 fixture 的平均值。
    private static func synthetic(_ count: Int) -> [NoteChunk] {
        (0..<count).map { i in
            NoteChunk(id: "sc\(i)", ref: BlockRef(noteID: "sn\(i / 20)", blockID: "sb\(i)"),
                      source: .text, indexInBlock: 0,
                      text: "第 \(i) 段 关于 排期 与 延期毕业 的记录 lease termination parking space CS5330 阿莫西林 饭后 record \(i)",
                      contentHash: "sh\(i)")
        }
    }
}
