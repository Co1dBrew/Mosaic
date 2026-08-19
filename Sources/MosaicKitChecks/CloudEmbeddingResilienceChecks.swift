import Foundation
import MosaicKit

/// # 云端 embedding 的失败注入与降级（本轮 §15 / §16）
///
/// 选择「云端优先」之前必须先证明**云端可以失败**。用 `StubURLProtocol` 打真实的
/// `CloudEmbeddingProvider` 网络路径，不需要服务器，也不看运气。
///
/// 核心不变量，一条都不能破：
///
/// > **Semantic failure ≠ Search failure。**
/// > 云端任何形态的失败都只能让语义路消失，keyword 路必须照常返回结果。
enum CloudEmbeddingResilienceChecks {

    static func provider(_ session: URLSession) -> CloudEmbeddingProvider {
        CloudEmbeddingProvider(baseURL: "https://stub.invalid/v1", apiKey: "k",
                               model: "bge-m3", dimension: 4, session: session)
    }

    static func embedding(_ values: [[Double]]) -> Data {
        let items = values.map { ["embedding": $0] }
        return try! JSONSerialization.data(withJSONObject: ["data": items])
    }

    static func run(_ r: CheckRunner) async {
        await checkFailureModes(r)
        await checkSearchSurvivesCloudFailure(r)
        await checkStaleProtectionUnderCloudLatency(r)
    }

    // MARK: §15 · 每一种失败形态都必须是「明确的错误」，不是脏数据

    static func checkFailureModes(_ r: CheckRunner) async {
        r.suite("Cloud 失败注入 —— 每种失败都要明确失败，不能写进索引")

        let session = StubURLProtocol.session()
        let p = provider(session)

        struct Scenario {
            let name: String
            let stub: StubURLProtocol.Stub
            /// 是否属于「可重试」—— 401/400 重试没有意义，429/5xx 才有。
            let retryable: Bool?
        }
        let scenarios: [Scenario] = [
            .init(name: "401 invalid key", stub: .init(statusCode: 401, body: Data(), error: nil), retryable: false),
            .init(name: "429 rate limited", stub: .init(statusCode: 429, body: Data(), error: nil), retryable: true),
            .init(name: "500 server error", stub: .init(statusCode: 500, body: Data(), error: nil), retryable: true),
            .init(name: "network offline", stub: .init(statusCode: 0, body: Data(),
                                                        error: URLError(.notConnectedToInternet)), retryable: true),
            .init(name: "timeout", stub: .init(statusCode: 0, body: Data(),
                                               error: URLError(.timedOut)), retryable: true),
            .init(name: "malformed body", stub: .init(statusCode: 200, body: Data("not json".utf8), error: nil), retryable: nil),
            .init(name: "empty embedding", stub: .init(statusCode: 200, body: embedding([[]]), error: nil), retryable: nil),
            .init(name: "dimension mismatch", stub: .init(statusCode: 200, body: embedding([[1, 2, 3, 4, 5, 6]]), error: nil), retryable: nil),
            .init(name: "count mismatch", stub: .init(statusCode: 200, body: embedding([[1, 2, 3, 4]]), error: nil), retryable: nil)
        ]

        for s in scenarios {
            StubURLProtocol.stub = s.stub
            var thrown: Error?
            do {
                // 两条输入：count mismatch 场景要靠它才暴露。
                _ = try await p.embed(batch: ["hello", "world"])
            } catch { thrown = error }

            r.expect(thrown != nil, "\(s.name) → 明确抛错，而不是返回一个能写进索引的向量")
            if let e = thrown as? EmbeddingProviderError, let retryable = s.retryable {
                // 可重试与不可重试必须分开：401 重试三次没有意义，429 / 5xx 才有。
                let isRetryable: Bool
                switch e {
                case .transport, .rateLimited, .unavailable: isRetryable = true
                case .rejected, .invalidInput:               isRetryable = false
                }
                r.expect(isRetryable == retryable,
                         "\(s.name) 的可重试性判定正确（\(isRetryable) == \(retryable)）")
            }
        }
        StubURLProtocol.stub = nil

        // 维度不符**宁可失败也不写入**：混进不可比的向量比没有向量更糟。
        StubURLProtocol.stub = .init(statusCode: 200, body: embedding([[1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 5, 6]]), error: nil)
        var rejected = false
        do { _ = try await p.embed(batch: ["a", "b"]) } catch { rejected = true }
        r.expect(rejected, "维度不符被拒绝在写入路径之外 —— 索引里绝不能混进不可比的向量")
        StubURLProtocol.stub = nil
    }

    // MARK: §15 · Semantic failure ≠ Search failure

    static func checkSearchSurvivesCloudFailure(_ r: CheckRunner) async {
        r.suite("Cloud 失败时搜索仍然可用（keyword 路不受影响）")

        let chunks = ChunkPipeline.chunks(
            noteID: "n1",
            blocks: [RetrievalFoundationChecks.textBlock("b1", "我问了 advisor 能不能延期一个学期毕业", order: 0),
                     RetrievalFoundationChecks.textBlock("b2", "周会上说排期结论下周三定", order: 1)],
            strategy: .block)
        let session = StubURLProtocol.session()

        for (name, stub) in [
            ("401", StubURLProtocol.Stub(statusCode: 401, body: Data(), error: nil)),
            ("429", StubURLProtocol.Stub(statusCode: 429, body: Data(), error: nil)),
            ("offline", StubURLProtocol.Stub(statusCode: 0, body: Data(), error: URLError(.notConnectedToInternet))),
            ("timeout", StubURLProtocol.Stub(statusCode: 0, body: Data(), error: URLError(.timedOut)))
        ] {
            StubURLProtocol.stub = stub
            let service = RetrievalService(provider: provider(session), vectors: InMemoryVectorStore())
            let outcome = await service.retrieve(query: "延期 毕业", chunks: chunks,
                                                 config: RetrievalConfig(version: "resilience", mode: .hybrid,
                                                                         chunkStrategy: .block, topK: 10))
            r.expect(!outcome.results.isEmpty,
                     "云端 \(name) 时 keyword 路照常返回结果（\(outcome.results.count) 条）—— Semantic failure ≠ Search failure")
            r.expect(outcome.results.allSatisfy { $0.vectorRank == nil },
                     "云端 \(name) 时向量路整条缺席，不是「部分参与」")
        }
        StubURLProtocol.stub = nil

        // 降级链：cloud 不可用 → local 可用时用 local，否则 keyword。
        // 这里验的是**路由决策**，provider 构造在 App 层（ProductionEmbedding）。
        r.expect(EmbeddingRouter.choose(corpusContainsHan: true, localChineseAvailable: true,
                                        localEnglishAvailable: true, cloudConfigured: false,
                                        cloudConsentGranted: false) == .localChinese,
                 "云端不可用 + 本地可用 → 降级到本地语义，而不是直接掉到 keyword")
        let noLocal = EmbeddingRouter.choose(corpusContainsHan: true, localChineseAvailable: false,
                                             localEnglishAvailable: false, cloudConfigured: false,
                                             cloudConsentGranted: false)
        if case .unavailable = noLocal {
            r.expect(true, "云端与本地都不可用 → 语义不可用，keyword 仍是最终保障")
        } else {
            r.expect(false, "云端与本地都不可用时应当 unavailable")
        }
    }

    // MARK: §16 · 云端越慢，stale 保护越重要

    static func checkStaleProtectionUnderCloudLatency(_ r: CheckRunner) async {
        r.suite("Cloud 高延迟下的 stale 保护 —— 迟到的旧结果必须被丢弃")

        // 场景：note v12 发起云端请求 → 用户编辑 → v13 → 1.3s 后 v12 的响应才回来。
        let v12 = "周会上说排期结论是下周三交付"
        let v13 = "周会上说排期结论推迟到下个月"
        let ref = BlockRef(noteID: "n1", blockID: "b1")
        let oldChunk = ChunkPipeline.chunks(noteID: "n1",
                                            blocks: [RetrievalFoundationChecks.textBlock("b1", v12, order: 0)],
                                            strategy: .block)[0]
        let newChunk = ChunkPipeline.chunks(noteID: "n1",
                                            blocks: [RetrievalFoundationChecks.textBlock("b1", v13, order: 0)],
                                            strategy: .block)[0]
        r.expect(oldChunk.contentHash != newChunk.contentHash, "v12 与 v13 的 contentHash 不同")

        // 迟到的 v12 结果试图写入，当前内容已经是 v13。
        let late = DerivedResult(key: EmbeddingJobKey(ref: ref, contentHash: oldChunk.contentHash,
                                                      embeddingVersion: "cloud-bge-m3-d1024"),
                                 payload: [Float](repeating: 0.1, count: 4))
        let now = DerivedWriteContext(noteExists: true, currentContentHash: newChunk.contentHash,
                                      currentEmbeddingVersion: "cloud-bge-m3-d1024")
        let decision = StaleGuard.decide(for: late, context: now)
        r.expect(!decision.isAccepted,
                 "1.3 秒后才回来的 v12 向量被丢弃 —— **云端延迟越高，这条越重要**")
        if case .contentChanged = decision.rejection {
            r.expect(true, "拒绝原因是 contentChanged，可归因")
        } else {
            r.expect(false, "拒绝原因应当是 contentChanged，实际 \(String(describing: decision.rejection))")
        }

        // 换 provider = 换向量空间，旧空间的迟到结果同样必须被拒。
        let wrongSpace = DerivedResult(key: EmbeddingJobKey(ref: ref, contentHash: newChunk.contentHash,
                                                            embeddingVersion: "nl-zh-Hans-r1"),
                                       payload: [Float](repeating: 0.1, count: 4))
        r.expect(!StaleGuard.decide(for: wrongSpace, context: now).isAccepted,
                 "从本地降级切到云端之后，本地那一批迟到结果也进不来（embeddingVersion 不符）")

        // 不靠取消：即使 provider 完全忽略取消也必须安全。
        r.expect(StaleGuard.decide(for: DerivedResult(
            key: EmbeddingJobKey(ref: ref, contentHash: newChunk.contentHash,
                                 embeddingVersion: "cloud-bge-m3-d1024"),
            payload: [Float](repeating: 0.1, count: 4)), context: now).isAccepted,
                 "内容与版本都对得上时照常接受 —— 保护的是正确性，不是把写入全关掉")
    }
}
