import XCTest
import MosaicKit

/// # 真机延迟基准（Metric A / Metric B-local）
///
/// ## 为什么只在物理设备上跑
///
/// 模拟器跑在 Mac 的 CPU 上，它的数字既不是 Mac 也不是 iPhone —— 拿它做发布判定
/// 是在用一台不存在的机器的性能下结论。所以这里**在模拟器上自动 skip**，
/// 不靠调用方记得加环境变量。
///
/// ## 为什么把网络单独排除在外
///
/// 云端 query embedding 的耗时**主要由地理位置决定**（实测 US→China 的 P95 是
/// 1317ms）。把它混进「检索延迟」会得到一个换服务商就作废的数字。
/// 所以这一套只测**不含网络的那几层**：
///
/// - **L1** keyword 路（分词 + 子串定位 + 排名）→ Metric A：用户多久看到第一批结果
/// - **L2a** 本地 query 嵌入（真实 `NLEmbedding`）
/// - **L2b** 余弦检索（确定性向量，纯数学，与模型无关）→ 规模曲线
/// - **L2** 本地 hybrid 端到端 = L2a + L2b + RRF → Metric B-local
///
/// ## 云端那一层（`test5`）单独一条，且**带 region 标签**
///
/// 它跟 L1/L2 混不得：本地那几层换台设备就要重测，云端这一层换个**区域**就要重测。
/// 所以 `test5` 把 `RunEnvironment` 的 `measuredLayer` 记成 `.semanticCloud`、
/// 把 region 一并记下来，并且**不设延迟阈值** —— `PerformanceGatePolicy.v2` 对这一层
/// 是「记录但不判定」，在这里加一个断言等于偷偷把 policy 改了。
///
/// 它存在的理由只有一个：**perf-v2 不受理 Mac 上跑出来的云端数字。**
/// 要让 cloud-hybrid 有资格进 Gate，就得有一份真机 release 的云端测量。
///
/// ## 同时验证 TD-9
///
/// 「iOS 上有没有中文句向量模型」这个问题一直是模拟器实测 + 真机待验证。
/// 这套用例跑起来的第一件事就是把真机的可用性矩阵打出来。
final class DeviceLatencyBenchmarkTests: XCTestCase {

    /// PRD 规定的四档规模。
    private let scales = [1_000, 5_000, 10_000, 20_000]
    private let dimension = 384

    private func skipUnlessPhysicalDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("真机基准：模拟器上的数字既不是 Mac 也不是 iPhone，自动跳过")
        #endif
    }

    // MARK: 0 · 环境元数据（不记录环境的性能数字不可用于判定）

    func test0_environment() throws {
        try skipUnlessPhysicalDevice()
        let env = RunEnvironment.capture()

        print("""

        ══════ 真机环境 ══════
        机型          \(env.deviceModel)
        系统          \(env.osVersion)
        构建配置      \(env.buildConfiguration)
        热状态        \(env.thermalState)
        低电量模式    \(env.lowPowerMode ? "开启 ⚠️ 会限频，结果不可用" : "关闭")
        """)

        XCTAssertFalse(env.lowPowerMode,
                       "低电量模式会限频 —— 关掉再跑，否则这批数字不能用于任何判定")
        XCTAssertEqual(env.buildConfiguration, "release",
                       "性能数字只能来自 release 构建。debug 在本项目实测慢 18 倍")
        XCTAssertEqual(env.thermalState, "nominal",
                       "设备已经在发热，先放凉再跑 —— 否则测的是降频后的性能")
    }

    // MARK: 1 · TD-9 真机可用性矩阵

    func test1_localModelAvailabilityOnRealHardware() throws {
        try skipUnlessPhysicalDevice()
        print("\n══════ TD-9 真机句向量模型可用性 ══════")
        var available: [String] = []
        for language in NLEmbeddingProvider.Language.allCases {
            let ok = NLEmbeddingProvider.isAvailable(language)
            let dim = (try? LocalEmbedding.make(language: language))?.modelInfo.dimension
            print("  \(language.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) "
                  + (ok ? "✅ \(dim.map { "\($0) 维" } ?? "可用但拿不到维度")" : "❌ 不可用"))
            if ok { available.append(language.rawValue) }
        }
        print("  → 真机可用：\(available.isEmpty ? "无" : available.joined(separator: ", "))")
        print("  模拟器实测曾是：zh-Hans ❌ · en ✅ 512 维；macOS 上 zh-Hans ✅ 640 维")
        // 不断言可用性 —— 这条用例的产出是**事实记录**，不是通过与否。
        XCTAssertTrue(true, "可用性矩阵已记录")
    }

    // MARK: 2 · Metric A —— keyword 快通道（不含网络，不含模型）

    func test2_metricA_keywordFastPath() async throws {
        try skipUnlessPhysicalDevice()

        // **走生产路径 `RetrievalService`，不是裸 `KeywordRetriever`。**
        //
        // 这一条以前直接调 `KeywordRetriever.retrieve` —— 于是 `NormalizedTextCache`
        // 落地之后它一点没变快，看起来像优化无效。实际是**它测的东西不是产品路径**：
        // 缓存装在 service 上，用户走的也是 service。
        // Metric A 是对用户的承诺，就必须在用户实际走的那条路上测。
        //
        // 冷热分开报：归一化缓存按 chunk 缓存，所以**语料变化后的第一次查询**要付全价。
        // 把冷启动混进平均值会低报首次搜索，单独报热的又会瞒下它。两个都报。
        print("\n══════ Metric A · keyword 快通道（生产路径 · Time to First Useful Result）══════")
        print(" chunks   冷P50   冷P95   热P50   热P95     提速   热状态")
        var rows: [(Int, Double, Double, Double, Double)] = []

        for scale in scales {
            let thermal = Self.coolUntilNominal()
            let chunks = Self.syntheticChunks(scale)
            let config = RetrievalConfig(version: "metric-a", mode: .keyword,
                                         embeddingProvider: "none", embeddingVersion: "none",
                                         chunkStrategy: .block, topK: 50)

            // 冷：每次查询都换一个全新 service，缓存永远是空的 ——
            // 对应「刚启动」「刚编辑过笔记」这两种真实情形。
            var cold: [Double] = []
            for i in 0..<Self.samples {
                let service = RetrievalService(provider: nil, vectors: InMemoryVectorStore())
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = await service.retrieve(query: Self.queries[i % Self.queries.count],
                                           chunks: chunks, config: config)
                cold.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            }

            // 热：同一个 service 连续查 —— 对应用户连着改关键词的那几秒。
            let service = RetrievalService(provider: nil, vectors: InMemoryVectorStore())
            _ = await service.retrieve(query: "预热", chunks: chunks, config: config)
            var warm: [Double] = []
            for i in 0..<Self.samples {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = await service.retrieve(query: Self.queries[i % Self.queries.count],
                                           chunks: chunks, config: config)
                warm.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            }

            let (cP50, cP95, _) = Self.percentiles(cold)
            let (wP50, wP95, _) = Self.percentiles(warm)
            rows.append((scale, cP50, cP95, wP50, wP95))
            print(String(format: " %6d %7.2f %7.2f %7.2f %7.2f   %5.2fx   %@",
                         scale, cP50, cP95, wP50, wP95, cP50 / max(wP50, 0.001), thermal as NSString))
        }

        // Metric A 是对用户的承诺，必须阻断。**冷热都要满足** ——
        // 「第一次搜索慢一倍」不是可以豁免的情形，那恰恰是用户最先遇到的一次。
        for (scale, cP50, cP95, wP50, wP95) in rows {
            XCTAssertLessThan(cP50, 100, "Metric A 冷 P50 < 100ms（\(scale) chunks 实测 \(cP50) ms）")
            XCTAssertLessThan(cP95, 250, "Metric A 冷 P95 < 250ms（\(scale) chunks 实测 \(cP95) ms）")
            XCTAssertLessThan(wP50, 100, "Metric A 热 P50 < 100ms（\(scale) chunks 实测 \(wP50) ms）")
            XCTAssertLessThan(wP95, 250, "Metric A 热 P95 < 250ms（\(scale) chunks 实测 \(wP95) ms）")
        }
        if let biggest = rows.last {
            XCTAssertLessThan(biggest.3, biggest.1,
                              "最大档上热查询应当明显快于冷查询 —— 否则 NormalizedTextCache 没生效")
        }
    }

    // MARK: 3 · L2b —— 余弦检索的规模曲线（纯数学，与模型无关）

    func test3_vectorSearchScaling() async throws {
        try skipUnlessPhysicalDevice()
        print("\n══════ L2b · 余弦检索规模曲线（dim \(dimension)，确定性向量）══════")
        print(" chunks        P50        P95     内存估算   热状态")
        for scale in scales {
            let thermal = Self.coolUntilNominal()
            let store = InMemoryVectorStore()
            for i in 0..<scale {
                let ref = BlockRef(noteID: "n\(i / 20)", blockID: "b\(i)")
                await store.upsert(EmbeddingRecord(
                    ref: ref, chunkID: "c\(i)", contentHash: "h\(i)",
                    embeddingVersion: "det-v1", dimension: dimension,
                    vector: MockEmbeddingProvider.deterministicVector(for: "c\(i)", dimension: dimension)))
            }
            let probe = MockEmbeddingProvider.deterministicVector(for: "probe", dimension: dimension)
            _ = await store.search(query: probe, topK: 50)
            var samples: [Double] = []
            for i in 0..<Self.samples {
                let q = MockEmbeddingProvider.deterministicVector(for: "q\(i)", dimension: dimension)
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = await store.search(query: q, topK: 50)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            }
            let (p50, p95, _) = Self.percentiles(samples)
            let mb = Double(scale * dimension * 4) / 1_048_576
            print(String(format: " %6d   %8.2f ms %8.2f ms   %6.1f MB   %@",
                         scale, p50, p95, mb, thermal as NSString))
        }
        XCTAssertTrue(true, "规模曲线已记录（真机数字，不与 Mac 混表）")
    }

    // MARK: 4 · Metric B-local —— 本地 hybrid 端到端（含真实模型的 query 嵌入）

    func test4_metricB_localHybridEndToEnd() async throws {
        try skipUnlessPhysicalDevice()
        guard let provider = Self.anyLocalProvider() else {
            print("\n══════ Metric B-local ══════\n  本机没有任何本地句向量模型 → 这台设备上语义路不可用（TD-9）")
            throw XCTSkip("没有本地模型，Metric B-local 在这台设备上不存在")
        }
        print("\n══════ Metric B-local · 本地 hybrid 端到端（provider \(provider.modelInfo.version)）══════")

        // L2a：只测 query 嵌入。**25 次而不是 6 次** —— 6 个样本的「P95」就是 max。
        //
        // 这一行的降温是必需的：`test3` 刚刚在 20k / 29.3 MB 的 store 上搜了 25 次，
        // 紧贴着测 L2a 会把上一条用例的余温算进来。第一次改完取样量时漏了它，
        // L2a 从 6.21 ms 读成 11.1 ms —— 那不是取样量的效果，是没放凉。
        let l2aThermal = Self.coolUntilNominal()
        _ = try? await provider.embed("预热")
        var embedSamples: [Double] = []
        for i in 0..<Self.samples {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try? await provider.embed(Self.queries[i % Self.queries.count])
            embedSamples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        }
        let (eP50, eP95, eMax) = Self.percentiles(embedSamples)

        // L2 端到端：走真实 RetrievalService（与生产同一条管线）
        print(" chunks        P50        P95        max   热状态")
        var endToEnd: [Int: Double] = [:]
        for scale in [1_000, 5_000, 20_000] {
            let thermal = Self.coolUntilNominal()
            let chunks = Self.syntheticChunks(scale)
            let store = InMemoryVectorStore()
            for c in chunks {
                await store.upsert(EmbeddingRecord(
                    ref: c.ref, chunkID: c.id, contentHash: c.contentHash,
                    embeddingVersion: provider.modelInfo.version,
                    dimension: provider.modelInfo.dimension,
                    vector: MockEmbeddingProvider.deterministicVector(
                        for: c.id, dimension: provider.modelInfo.dimension)))
            }
            let service = RetrievalService(provider: provider, vectors: store)
            let config = RetrievalConfig(version: "device-bench", mode: .hybrid,
                                         embeddingProvider: provider.modelInfo.identifier,
                                         embeddingVersion: provider.modelInfo.version,
                                         chunkStrategy: .block, topK: 50)
            _ = await service.retrieve(query: "预热", chunks: chunks, config: config)
            var samples: [Double] = []
            for i in 0..<Self.samples {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = await service.retrieve(query: Self.queries[i % Self.queries.count],
                                           chunks: chunks, config: config)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            }
            let (p50, p95, mx) = Self.percentiles(samples)
            endToEnd[scale] = p50
            print(String(format: " %6d   %8.2f ms %8.2f ms %8.2f ms   %@",
                         scale, p50, p95, mx, thermal as NSString))
        }

        // ── L2a **只能跟着同批次的端到端一起报** ──
        //
        // 它的绝对值三次读数是 6.21 → 11.1 → 4.3 ms，而它自己的代码一行没动。
        // 热状态 / 取样量 / 前面跑了什么全部排除过，机制没查清（§23.6 / §24.5）。
        // 结论是：**这个数字会被同进程别处的改动影响，不可独立引用。**
        //
        // 所以不再单独打印它，而是连着「占同一批次端到端的比例」一起打印 ——
        // 占比是同批次内的相对量，天然带着上下文。想引用绝对值，
        // 就必须把同批次的端到端一起抄走。
        if let base = endToEnd[20_000] {
            print(String(format: " L2a query 嵌入      P50 %6.2f ms  P95 %6.2f ms  max %6.2f ms   热状态 %@",
                         eP50, eP95, eMax, l2aThermal as NSString))
            print(String(format: "                     ↳ 占同批次 20k 端到端 P50 的 %.1f%%", eP50 / base * 100))
            print("                     ⚠️ **绝对值不可单独引用**（三次读数 6.21 / 11.1 / 4.3，机制未查清）；")
            print("                        要引就连同上面这张表一起引。")
            XCTAssertLessThan(eP50, base,
                              "L2a 是端到端的一个分量，必须小于端到端本身 —— "
                              + "不满足说明两者不是同一批次测的，那时它更加不可引用")
        }
        print(" 注：向量用确定性值填充 —— 这里测的是**延迟**，不是质量。")
        print(" 注：取样量 25（P95 = 第 24/25 位）。2026-08-19 前用的是 20，那时的「P95」等于 max。")
        XCTAssertTrue(true, "Metric B-local 已记录")
    }

    // MARK: 5 · Metric B-cloud —— 真机上的云端语义（含一次网络往返）

    /// # 为什么单独一条，而不是把云端塞进 `test4`
    ///
    /// `test4` 测的是**本机算力**，换台设备就要重测；这一条测的是**网络**，
    /// 换个区域就要重测。两者放进同一张表，读表的人无法判断某个数字变了是因为
    /// 换了手机还是换了机场。
    ///
    /// # 为什么规模曲线只跑最大档
    ///
    /// **网络往返与索引规模无关。** 1k 和 20k 的 query 嵌入是同一个 HTTP 请求，
    /// 把它跑四遍只是把同一个数字花四份钱测四次。所以：
    ///
    /// - **L3**（网络 / 解析分段）单独测，不分档 —— 它本来就不随规模变
    /// - **L4**（端到端）只在 20k 上跑一次，用来回答「最坏情况下总共多久」
    ///
    /// # 断言断的是什么
    ///
    /// **不断延迟。** perf-v2 对 Metric B-cloud 是「记录但不判定」，
    /// 在这里加一条 `XCTAssertLessThan(p95, …)` 等于绕过 policy 偷偷改判定口径。
    /// 这一条断的是**这批数字有没有资格被引用**：环境是否合格、region 有没有记下来、
    /// 以及「耗时主要在网络」这个结构性主张在真机上还成不成立。
    func test5_metricB_cloudSemantic() async throws {
        try skipUnlessPhysicalDevice()

        guard let creds = Self.cloudCredentials() else {
            // 缺凭据不算失败 —— 但要把「为什么跳过」说清楚，否则下一个人会以为它跑过了。
            print("""

            ══════ Metric B-cloud —— 跳过 ══════
              没读到云端凭据。真机测试进程**读不到 Mac shell 的环境变量**
              （`TEST_RUNNER_` 前缀对 app-hosted 单元测试无效，已实测确认），
              所以凭据要打进测试 bundle：

                建 App/MosaicBench/CloudCredentials.json（已在 .gitignore 里）：
                { "base": "https://…/v1", "key": "sk-…",
                  "model": "BAAI/bge-m3", "dim": 1024, "region": "cn-shanghai" }

              然后重新跑 xcodebuild 即可 —— 它由一个脚本阶段可选拷贝进 bundle，
              **不需要 xcodegen generate**，有没有这个文件都能构建成功。
              跑完把它删掉。
            """)
            throw XCTSkip("没有云端凭据，Metric B-cloud 未测量 —— 结论是「待验证」，不是「通过」")
        }
        let (base, key, model, dim, region) = (creds.base, creds.key, creds.model, creds.dim, creds.region)

        // 这批数字的身份证。**测量环境是判定前置条件，不是脚注**（架构记录 §22.2）。
        let runEnv = RunEnvironment.capture(layer: .semanticCloud, providerRegion: region)
        print("""

        ══════ Metric B-cloud · 真机云端语义（model \(model) · dim \(dim)）══════
          机型 \(runEnv.deviceModel)   系统 \(runEnv.osVersion)   构建 \(runEnv.buildConfiguration)
          热状态 \(runEnv.thermalState)   低电量 \(runEnv.lowPowerMode ? "开启 ⚠️" : "关闭")
          区域 \(region ?? "⚠️ 未记录 —— 云端延迟不带 region 不可比")
        """)

        let latency = EmbeddingLatencyRecorder()
        let provider = CloudEmbeddingProvider(baseURL: base, apiKey: key, model: model,
                                              dimension: dim, latency: latency)

        // ── L3 · 网络与解析分开计时（不分档：网络往返与索引规模无关）──
        do {
            _ = try await provider.embed("预热")      // 预热：首次请求含 TLS 握手，不计入
        } catch {
            // **有凭据却打不通 → 失败，不是 skip。**「没配」和「配了但没生效」
            // 补救动作完全不同：前者是「本轮不测云端」，后者是「你以为你在测，其实没测」。
            // 后者若也判 skip，跑批会绿着结束，而一个数字都没有采到。
            XCTFail("""
                云端不可达：\(error)
                最可能的原因是 key 已被撤销或过期（本项目的 key 因为贴进过对话记录被撤销过多次）。
                先在 Mac 上验一把再重跑：
                  curl -s -o /dev/null -w '%{http_code}\\n' -X POST <base>/embeddings \\
                    -H "Authorization: Bearer <key>" -H 'Content-Type: application/json' \\
                    -d '{"model":"<model>","input":["测试"]}'
                **不要把这次失败当成延迟结论** —— 一个数字都没采到。
                """)
            return
        }
        await latency.reset()
        // **25 次，不是 6 次。** `percentiles` 取的是 `s[min(count-1, Int(count*0.95))]`
        // —— 当 count ≤ 20 时这个下标就是最后一位，**P95 等于 max**，
        // 报出来的「P95」其实是「单次最差请求」。25 起才是第 24/25 位，是真百分位。
        var failures = 0
        for i in 0..<Self.samples {
            do { _ = try await provider.embed(Self.queries[i % Self.queries.count]) }
            catch { failures += 1 }
        }
        let p = await latency.percentiles()
        print(String(format: "  L3 网络往返        P50 %8.2f ms  P95 %8.2f ms", p.networkP50, p.networkP95))
        print(String(format: "  L3 解析 + 归一化   P50 %8.2f ms  P95 %8.2f ms", p.decodeP50, p.decodeP95))
        let networkShare = p.networkP50 / max(p.networkP50 + p.decodeP50, 0.0001) * 100
        print(String(format: "  → 网络占 %.2f%%（样本 %d 次，失败 %d 次）", networkShare, p.count, failures))

        let usage = await latency.promptTokenTotal()
        if usage.reportedCalls > 0 {
            print("  这一轮 query 嵌入共 \(usage.tokens) prompt_tokens（服务端回报）")
        }
        let thermal = Self.coolUntilNominal()

        // ── L4 · 端到端，只在最大档 ──
        //
        // 向量用确定性值填充：这里测的是**延迟**，不是质量。质量在 Mac 侧用真实语料
        // 跑五路对照（`mosaic-checks`），两者不可互相冒充。
        let scale = 20_000
        let chunks = Self.syntheticChunks(scale)
        let store = InMemoryVectorStore()
        for c in chunks {
            await store.upsert(EmbeddingRecord(
                ref: c.ref, chunkID: c.id, contentHash: c.contentHash,
                embeddingVersion: provider.modelInfo.version, dimension: dim,
                vector: MockEmbeddingProvider.deterministicVector(for: c.id, dimension: dim)))
        }
        let service = RetrievalService(provider: provider, vectors: store)
        let config = RetrievalConfig(version: "device-bench-cloud", mode: .hybrid,
                                     embeddingProvider: provider.modelInfo.identifier,
                                     embeddingVersion: provider.modelInfo.version,
                                     chunkStrategy: .block, topK: 50)
        _ = await service.retrieve(query: "预热", chunks: chunks, config: config)
        var samples: [Double] = []
        for i in 0..<Self.samples {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = await service.retrieve(query: Self.queries[i % Self.queries.count],
                                       chunks: chunks, config: config)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        }
        let (p50, p95, mx) = Self.percentiles(samples)
        let mb = Double(scale * dim * 4) / 1_048_576
        print(String(format: "  L4 端到端 %d chunks   P50 %8.2f ms  P95 %8.2f ms  max %8.2f ms（向量 %.1f MB · 热状态 %@ · 取样 %d）",
                     scale, p50, p95, mx, mb, thermal as NSString, Self.samples))
        print("  ⚠️ 只跑了一轮。云端延迟属于当天的网络 —— **一次不能当定值**，要引用请跑多轮报区间。")

        // ── 断言：资格与结构，**不断延迟** ──
        XCTAssertEqual(failures, 0, "\(Self.samples) 次 query 嵌入不应有失败 —— 有失败则这批延迟数字不完整")
        XCTAssertNil(PerformanceGatePolicy.v2.disqualification(runEnv),
                     "这批数字必须有资格参与 perf-v2 判定 —— 这正是它要在真机上跑的原因；"
                     + "不合格就说明设备状态不对（debug / 低电量 / 发热），换状态重跑")
        XCTAssertNotNil(region,
                        "云端延迟必须带 region —— 不带 region 的数字换个区域即作废，"
                        + "给 MOSAIC_LIVE_EMBEDDING_REGION")
        XCTAssertGreaterThan(p.networkP50, p.decodeP50 * 10,
                             String(format: "耗时应当由网络主导（网络 %.2f ms vs 解析 %.2f ms）—— "
                                    + "这是「Metric B-cloud 不该套用 Metric A 预算」的依据；"
                                    + "若在真机上不成立，说明该重新审视分层假设",
                                    p.networkP50, p.decodeP50))
        XCTAssertGreaterThan(p50, p.networkP50 * 0.5,
                             "端到端应当明显包含那次网络往返 —— 否则说明 hybrid 根本没走语义路")
    }

    // MARK: 6 · Golden Set eval 整体跑在真机上 —— 质量与延迟出自**同一次跑批**

    /// # 这一条补的是 Gate 判定缺的最后一块
    ///
    /// `test2`–`test5` 测的都是**延迟**，质量数字一直来自 Mac 侧的 `mosaic-checks`。
    /// 而 `ReleaseGate.evaluate` 读的是**同一个 `EvalRun`** 里的 recall / MRR / p95 ——
    /// 把「Mac 上的质量」和「真机上的延迟」拼进一次判定，正是这个项目一直在防的事。
    ///
    /// 所以这一条把 `EvalRunner` 整个搬上设备：同一次跑批同时产出质量与延迟，
    /// 配一份合格的 `RunEnvironment`，然后跑**真实**的 Gate 判定。
    ///
    /// # 判定不是这条用例的断言
    ///
    /// 它照报 PASS / BLOCKED / STALE，但**只断言判定成立**（不是 STALE、四项都产出）。
    /// 断言某个 status 等于把评测结论钉死在断言里 —— 数据一变用例就红，
    /// 而那时候该改的是结论，不是用例。
    ///
    /// # 它仍然不能证明「可以上线」
    ///
    /// 评测集是 synthetic。这条用例证明的是**判定链路在真机上闭合了**，
    /// 不是「检索质量达到了发布标准」。
    func test6_goldenSetEvalOnDevice() async throws {
        try skipUnlessPhysicalDevice()
        guard let data = Self.goldenSetData() else {
            throw XCTSkip("测试 bundle 里没有 HumanLikeGoldenSet.json —— 检查 project.yml 的 sources")
        }
        let dataset = try GoldenSetFixture.decode(data)
        guard let local = Self.anyLocalProvider() else {
            throw XCTSkip("本机没有句向量模型，语义路在这台设备上不存在（TD-9）")
        }
        let chunks = dataset.chunks
        let cases = dataset.evalCases
        let negatives = dataset.negativeEvalCases

        print("""

        ══════ Golden Set eval on device（\(dataset.version)）══════
          \(dataset.notes.count) notes / \(chunks.count) chunks / \(cases.count) 正例 / \(negatives.count) 负例
          provider \(local.modelInfo.version)
        """)

        // ── 本地索引（真机上真的嵌一遍，不用确定性向量占位）──
        //
        // `test4` 用确定性向量是因为它只测延迟；这里要出**质量**数字，
        // 向量必须是真的，否则 recall 没有意义。
        Self.coolUntilNominal()
        let t0 = DispatchTime.now().uptimeNanoseconds
        let localStore = InMemoryVectorStore()
        for start in stride(from: 0, to: chunks.count, by: 32) {
            let slice = Array(chunks[start..<min(start + 32, chunks.count)])
            guard let vectors = try? await local.embed(batch: slice.map(\.text)) else { continue }
            for (chunk, vector) in zip(slice, vectors) {
                await localStore.upsert(EmbeddingRecord(
                    ref: chunk.ref, chunkID: chunk.id, chunkIndex: chunk.indexInBlock,
                    contentHash: chunk.contentHash, embeddingVersion: local.modelInfo.version,
                    chunkStrategy: chunk.strategy, dimension: vector.count, vector: vector))
            }
        }
        let indexMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        print(String(format: "  本地建索引 %.0f ms（%.1f ms per chunk）", indexMs, indexMs / Double(chunks.count)))

        // ── 各臂跑批 ──
        var runs: [(arm: String, layer: MeasuredLatencyLayer, run: EvalRun, neg: EvalRun)] = []

        func evaluate(_ arm: String, mode: RetrievalMode, provider: (any EmbeddingProvider)?,
                      store: InMemoryVectorStore, layer: MeasuredLatencyLayer) async {
            let service = RetrievalService(provider: provider, vectors: store)
            let config = RetrievalConfig(version: arm, mode: mode,
                                        embeddingProvider: provider?.modelInfo.identifier ?? "none",
                                        embeddingVersion: provider?.modelInfo.version ?? "none",
                                        chunkStrategy: .default, topK: 10)
            let runner = EvalRunner(service: service, chunksProvider: { chunks })
            guard let run = try? await runner.run(cases: cases, config: config),
                  let neg = try? await runner.run(cases: negatives, config: config) else {
                XCTFail("\(arm) 跑批失败"); return
            }
            runs.append((arm, layer, run, neg))
        }

        Self.coolUntilNominal()
        await evaluate("keyword", mode: .keyword, provider: nil,
                       store: InMemoryVectorStore(), layer: .firstResult)
        Self.coolUntilNominal()
        await evaluate("local-hybrid", mode: .hybrid, provider: local,
                       store: localStore, layer: .semanticLocal)

        // 云端臂：有凭据才跑。**在设备上真的嵌一遍全库** —— 这是它跟 Mac 侧
        // 那次跑批唯一的实质区别，也是 perf-v2 只受理真机数字的原因。
        if let creds = Self.cloudCredentials() {
            let cloud = CloudEmbeddingProvider(baseURL: creds.base, apiKey: creds.key,
                                               model: creds.model, dimension: creds.dim)
            let cloudStore = InMemoryVectorStore()
            var ok = true
            for start in stride(from: 0, to: chunks.count, by: 32) {
                let slice = Array(chunks[start..<min(start + 32, chunks.count)])
                do {
                    let vectors = try await cloud.embed(batch: slice.map(\.text))
                    for (chunk, vector) in zip(slice, vectors) {
                        await cloudStore.upsert(EmbeddingRecord(
                            ref: chunk.ref, chunkID: chunk.id, chunkIndex: chunk.indexInBlock,
                            contentHash: chunk.contentHash, embeddingVersion: cloud.modelInfo.version,
                            chunkStrategy: chunk.strategy, dimension: vector.count, vector: vector))
                    }
                } catch {
                    XCTFail("云端建索引失败：\(error) —— 有凭据却打不通，这批数字不完整")
                    ok = false; break
                }
            }
            if ok {
                Self.coolUntilNominal()
                await evaluate("cloud-hybrid", mode: .hybrid, provider: cloud,
                               store: cloudStore, layer: .semanticCloud)
            }
        } else {
            print("  云端臂：跳过（没有 CloudCredentials.json）")
        }

        print("  arm            R@1     R@3     R@5     MRR      P50      P95   no-result")
        for r in runs {
            let m = r.run.inScopeMetrics
            print(String(format: "  %-13@ %.3f   %.3f   %.3f   %.3f  %7.2fms %7.2fms   %5.1f%%",
                         r.arm as NSString, m.recallAt1, m.recallAt3, m.recallAt5, m.mrr,
                         m.p50Ms, m.p95Ms, r.neg.metrics.noResultAccuracy * 100))
        }

        // ── 真实 Gate 判定：**质量与延迟出自同一个 EvalRun** ──
        //
        // **baseline 要选「现在生产用的那套」，不是最弱的那套。** 第一版给所有
        // candidate 都配 keyword 做 baseline，于是 cloud-hybrid 的 Recall@5 检查变成
        // 「1.000 ≥ 0.343」—— 一关等于没设。那是 D-UI-DEV-008 想拦的失败形态
        // 换了身衣服：不是加权放行，是**挑一个软的对照**放行。
        //
        // 所以按「谁会被它替掉」配：
        //   local-hybrid  的对照是 keyword      （语义路上线前的现状）
        //   cloud-hybrid  的对照是 local-hybrid （现在生产在跑的隐式 Hybrid）
        func baseline(for arm: String) -> String { arm == "cloud-hybrid" ? "local-hybrid" : "keyword" }

        for candidate in runs where candidate.arm != "keyword" {
            guard let baseline = runs.first(where: { $0.arm == baseline(for: candidate.arm) }) else {
                XCTFail("\(candidate.arm) 的 baseline 缺失"); continue
            }
            let env = RunEnvironment.capture(
                layer: candidate.layer,
                providerRegion: candidate.layer == .semanticCloud ? Self.cloudCredentials()?.region : nil)
            let decision = ReleaseGate.evaluate(
                configVersion: candidate.arm,
                // `EvalRunner` 把 `config.version` 写进 `run.configVersion`，
                // 而这里的 config.version 就是 arm 名 —— 所以版本号天然对得上，
                // 不需要改写。Gate 只核对 current 的版本号，baseline 的不核。
                current: candidate.run,
                baseline: baseline.run,
                thresholds: GateThresholds(performance: .v2),
                environment: env)

            print("""

              ── Gate（candidate \(candidate.arm) · baseline \(baseline.arm) · layer \(candidate.layer.rawValue)）──
              环境 \(env.deviceClass.rawValue)/\(env.buildConfiguration)/\(env.thermalState)\(env.providerRegion.map { " · region \($0)" } ?? "")
              判定 \(decision.headline)
            """)
            for reason in decision.blockingReasons { print("        · \(reason)") }
            for c in decision.checks {
                print(String(format: "        %@ %-22@ %-30@ 要求 %@", c.passed ? "✅" : "❌",
                             c.kind.label as NSString, c.actualText as NSString, c.conditionText))
            }

            // 断言判定**成立**，不断言它等于哪一个 status。
            XCTAssertNil(PerformanceGatePolicy.v2.disqualification(env),
                         "\(candidate.arm)：真机 release + nominal 的数字必须有资格参与判定")
            XCTAssertNotEqual(decision.status, .stale,
                              "\(candidate.arm)：这是真机跑批，不该判 STALE —— "
                              + "STALE 说明环境或版本号对不上，那是配置问题不是质量问题")
            XCTAssertEqual(decision.checks.count, 4, "\(candidate.arm)：四项检查全部产出")
        }

        print("""

          ⚠️ 判定链路在真机上闭合了 —— 质量与延迟出自同一次跑批、同一份环境元数据。
             但**评测集仍是 synthetic**，所以 PASS 不等于「可以上线」。
             正式结论要等真实笔记上的人工标注（backlog P0）。
        """)
    }

    // MARK: 工具

    /// 云端凭据。**不进仓库、不进环境变量。**
    ///
    /// 环境变量这条路在真机上走不通：测试进程跑在设备上，读不到 Mac shell 的 env，
    /// 而 `xcodebuild test … TEST_RUNNER_FOO=bar` 那套只对 UI test 的 runner app 生效
    /// —— 本项目实测，app-hosted 单元测试里一个 `MOSAIC_*` 都看不到。
    ///
    /// 所以走 bundle 资源：一个 gitignored 的 JSON 由构建脚本**可选**拷进测试 bundle
    /// （见 `project.yml` 的 `postBuildScripts`）—— 有它就真实测量，没有就 skip，
    /// 两种情况都能构建成功。
    /// 仍然保留环境变量分支，因为模拟器/Mac 侧用得上，且与 `mosaic-checks` 口径一致。
    struct CloudCredentials {
        let base: String, key: String, model: String
        let dim: Int
        let region: String?
    }

    /// 从测试 bundle 读 golden set。**它是仓库里那唯一一份 JSON**
    /// （`project.yml` 直接引用 `../Sources/MosaicKitChecks/Fixtures/`），
    /// 所以真机与 Mac 跑的是同一个评测集 —— 这是两边数字可比的前提。
    private static func goldenSetData() -> Data? {
        guard let url = Bundle(for: DeviceLatencyBenchmarkTests.self)
                .url(forResource: "HumanLikeGoldenSet", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func cloudCredentials() -> CloudCredentials? {
        let env = ProcessInfo.processInfo.environment
        if let base = env["MOSAIC_LIVE_EMBEDDING_BASE"], !base.isEmpty,
           let key = env["MOSAIC_LIVE_EMBEDDING_KEY"], !key.isEmpty {
            return CloudCredentials(base: base, key: key,
                                    model: env["MOSAIC_LIVE_EMBEDDING_MODEL"] ?? "BAAI/bge-m3",
                                    dim: Int(env["MOSAIC_LIVE_EMBEDDING_DIM"] ?? "1024") ?? 1024,
                                    region: env["MOSAIC_LIVE_EMBEDDING_REGION"])
        }
        guard let url = Bundle(for: DeviceLatencyBenchmarkTests.self)
                .url(forResource: "CloudCredentials", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        struct File: Decodable {
            let base: String, key: String
            let model: String?, region: String?
            let dim: Int?
        }
        guard let f = try? JSONDecoder().decode(File.self, from: data),
              !f.base.isEmpty, !f.key.isEmpty else { return nil }
        return CloudCredentials(base: f.base, key: f.key,
                                model: f.model ?? "BAAI/bge-m3",
                                dim: f.dim ?? 1024, region: f.region)
    }

    private static let queries = ["延期毕业", "排期结论", "lease termination",
                                  "CS5330", "阿莫西林 饭后", "parking space"]

    /// 全部延迟用例的取样量。**下限由 `percentiles` 的实现决定，不是随手挑的**：
    /// 它取 `s[min(count-1, Int(count*0.95))]`，`count ≤ 20` 时下标落在最后一位，
    /// 于是「P95」退化成 **max** —— 一次抖动就能让整轮数字翻几倍
    /// （云端实测见过 610 ms → 2871 ms）。25 起下标是第 24/25 位，P95 才是百分位。
    ///
    /// 历史：`test4` 曾用 6（L2a）和 20（端到端），所以 2026-08-19 之前记录的
    /// 「Metric B-local P95 119.30 / 143.23 ms」**其实是 max**。那批数字已作废，
    /// 因为它还被当成 D-AI-003「本地 hybrid 在 SLO 内」的实测依据用过。
    private static let samples = 25

    private static func syntheticChunks(_ count: Int) -> [NoteChunk] {
        (0..<count).map { i in
            NoteChunk(id: "c\(i)",
                      ref: BlockRef(noteID: "n\(i / 20)", blockID: "b\(i)"),
                      source: .text, indexInBlock: 0,
                      text: "第 \(i) 段 关于 排期 与 延期毕业 的记录 lease termination parking space CS5330 阿莫西林 饭后 record \(i)",
                      contentHash: "h\(i)")
        }
    }

    private static func anyLocalProvider() -> (any EmbeddingProvider)? {
        for language in NLEmbeddingProvider.Language.allCases {
            if let p = try? LocalEmbedding.make(language: language) { return p }
        }
        return nil
    }

    private static func percentiles(_ samples: [Double]) -> (Double, Double, Double) {
        let s = samples.sorted()
        return (s[s.count / 2],
                s[min(s.count - 1, Int(Double(s.count) * 0.95))],
                s.last ?? 0)
    }

    /// 每档之间放凉，**并把实际等到的热状态返回**。
    ///
    /// 原来是无条件 `sleep(1.0)` —— 一秒钟凉不下来，于是后面几档测的是降频后的性能，
    /// 而报表上看不出来。这是「同一台设备两次跑批 20k P95 从 119 到 143 ms」的
    /// 主要嫌疑之一（另一个是取样量，见 `samples`）。
    ///
    /// 两点设计：
    /// 1. **有上限。** 等不回 `nominal` 就不等了 —— 一个会挂住几分钟的基准没人会跑。
    /// 2. **返回实际状态，由调用方打进表里。** 等不回来不是失败，
    ///    但**必须如实标注**，否则读表的人无法判断某一行是不是降频数据。
    @discardableResult
    private static func coolUntilNominal(timeout: TimeInterval = 45) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while ProcessInfo.processInfo.thermalState != .nominal && Date() < deadline {
            Thread.sleep(forTimeInterval: 1.0)
        }
        Thread.sleep(forTimeInterval: 1.0)   // 即使已经 nominal 也缓一下，别贴着上一档跑
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return "nominal"
        case .fair:     return "fair⚠️"
        case .serious:  return "serious⚠️"
        case .critical: return "critical⚠️"
        @unknown default: return "unknown⚠️"
        }
    }
}
