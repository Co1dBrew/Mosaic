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
/// 云端那一层（L3 网络 / L4 总计）由 Mac 侧单独测量并带 region 标签，见架构记录。
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

    func test2_metricA_keywordFastPath() throws {
        try skipUnlessPhysicalDevice()
        print("\n══════ Metric A · keyword 快通道（Time to First Useful Result）══════")
        print(" chunks        P50        P95        max")
        var rows: [(Int, Double, Double)] = []
        for scale in scales {
            let chunks = Self.syntheticChunks(scale)
            _ = KeywordRetriever.retrieve(query: "预热", chunks: chunks, topK: 50)
            var samples: [Double] = []
            for i in 0..<25 {
                let query = Self.queries[i % Self.queries.count]
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = KeywordRetriever.retrieve(query: query, chunks: chunks, topK: 50)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            }
            let (p50, p95, mx) = Self.percentiles(samples)
            rows.append((scale, p50, p95))
            print(String(format: " %6d   %8.2f ms %8.2f ms %8.2f ms", scale, p50, p95, mx))
            Self.cool()
        }
        // Metric A 是对用户的承诺，必须阻断。
        for (scale, p50, p95) in rows {
            XCTAssertLessThan(p50, 100, "Metric A P50 < 100ms（\(scale) chunks 实测 \(p50) ms）")
            XCTAssertLessThan(p95, 250, "Metric A P95 < 250ms（\(scale) chunks 实测 \(p95) ms）")
        }
    }

    // MARK: 3 · L2b —— 余弦检索的规模曲线（纯数学，与模型无关）

    func test3_vectorSearchScaling() async throws {
        try skipUnlessPhysicalDevice()
        print("\n══════ L2b · 余弦检索规模曲线（dim \(dimension)，确定性向量）══════")
        print(" chunks        P50        P95     内存估算")
        for scale in scales {
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
            for i in 0..<25 {
                let q = MockEmbeddingProvider.deterministicVector(for: "q\(i)", dimension: dimension)
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = await store.search(query: q, topK: 50)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            }
            let (p50, p95, _) = Self.percentiles(samples)
            let mb = Double(scale * dimension * 4) / 1_048_576
            print(String(format: " %6d   %8.2f ms %8.2f ms   %6.1f MB", scale, p50, p95, mb))
            Self.cool()
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

        // L2a：只测 query 嵌入
        _ = try? await provider.embed("预热")
        var embedSamples: [Double] = []
        for q in Self.queries {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try? await provider.embed(q)
            embedSamples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        }
        let (eP50, eP95, _) = Self.percentiles(embedSamples)
        print(String(format: " L2a query 嵌入      P50 %6.2f ms  P95 %6.2f ms", eP50, eP95))

        // L2 端到端：走真实 RetrievalService（与生产同一条管线）
        print(" chunks        P50        P95")
        for scale in [1_000, 5_000, 20_000] {
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
            for i in 0..<20 {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = await service.retrieve(query: Self.queries[i % Self.queries.count],
                                           chunks: chunks, config: config)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            }
            let (p50, p95, _) = Self.percentiles(samples)
            print(String(format: " %6d   %8.2f ms %8.2f ms", scale, p50, p95))
            Self.cool()
        }
        print(" 注：向量用确定性值填充 —— 这里测的是**延迟**，不是质量。")
        XCTAssertTrue(true, "Metric B-local 已记录")
    }

    // MARK: 工具

    private static let queries = ["延期毕业", "排期结论", "lease termination",
                                  "CS5330", "阿莫西林 饭后", "parking space"]

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

    /// 每档之间放凉一下 —— 连续满载会热降频，那时测的是降频后的性能。
    private static func cool() { Thread.sleep(forTimeInterval: 1.0) }
}
