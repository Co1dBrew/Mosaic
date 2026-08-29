import Foundation
import MosaicKit

/// TD-5 —— 真实 embedding provider。
///
/// 这一组检查的目的不是「代码能跑」，而是**证明语义检索真的成立**：
/// 语义相关但字面不重合的 query 能不能把正确的笔记排到前面。
/// 在 mock provider 上这件事永远为假，所以 Week 4 的 Recall 必须建立在这里之后。
enum EmbeddingProviderChecks {

    /// 一份刻意设计的语料：query 与目标笔记**字面几乎不重合**，只能靠语义。
    static let corpus: [(text: String, id: String)] = [
        ("我问了 advisor 能不能延期一个学期毕业，他说要先跟系里确认", "delay"),
        ("学生如需延期毕业，应在学期开始前四周向学院提交书面申请", "policy"),
        ("周会上说延期的事下周开会再定，毕业时间还有缓冲", "meeting"),
        ("今天把合同评审的三处修改整理好了", "contract"),
        ("读《人类简史》第四章，围绕认知革命展开", "book"),
        ("现场照片：设备安装位置与线路走向", "photo"),
        ("下午三点和产品过一遍 Q3 排期", "schedule"),
        ("楼下那家面馆的辣椒油很香", "noodle")
    ]

    /// query → 可接受的正确答案集合。
    static let queries: [(q: String, expected: Set<String>)] = [
        ("我之前问学校能不能晚一点毕业的事情", ["delay", "policy", "meeting"]),
        ("合同要改哪些地方", ["contract"]),
        ("认知革命", ["book"]),
        ("排期会议", ["schedule"]),
        ("吃饭", ["noodle"])
    ]

    static func run(_ r: CheckRunner) async {
        r.suite("TD-5 · 真实本地 embedding（Apple NaturalLanguage）")

        guard NLEmbeddingProvider.isAvailable(.simplifiedChinese) else {
            r.expect(true, "本机无 zh-Hans 句向量模型，跳过（CI 环境差异，不算失败）")
            return
        }
        guard let provider = try? LocalEmbedding.make() else {
            r.expect(false, "isAvailable 为真但构造失败 —— 两者必须一致")
            return
        }

        // ── 基本契约 ──
        r.expect(provider.modelInfo.dimension == 640, "zh-Hans 句向量 640 维（得到 \(provider.modelInfo.dimension)）")
        r.expect(provider.modelInfo.version.contains("zh-Hans"),
                 "语言被编进 version —— 换语言必须让索引失效（\(provider.modelInfo.version)）")

        let v1 = try? await provider.embed("延期毕业")
        let v2 = try? await provider.embed("延期毕业")
        r.expect(v1 != nil, "能产出向量")
        r.expect(v1 == v2, "同输入同输出（可复现，评测的前提）")
        r.expect(v1?.count == provider.modelInfo.dimension, "维度与声明一致")
        let norm = (v1 ?? []).reduce(0) { $0 + $1 * $1 }
        r.expect(abs(norm - 1.0) < 0.001, "已 L2 归一化")
        do { _ = try await provider.embed("   "); r.expect(false, "空输入应报错") }
        catch { r.expect(true, "空输入被拒绝") }

        // 英文模型是 512 维 —— 与中文 640 维不同空间。混用无意义，
        // 所以 version 必须不同。
        if let en = try? LocalEmbedding.make(language: .english) {
            r.expect(en.modelInfo.version != provider.modelInfo.version,
                     "中英文 provider 的 version 不同（维度 \(en.modelInfo.dimension) vs \(provider.modelInfo.dimension)）")
        }

        // ── 真正的判据：语义检索是否成立 ──
        let store = InMemoryVectorStore()
        var idByChunk: [String: String] = [:]
        for (i, doc) in corpus.enumerated() {
            guard let v = try? await provider.embed(doc.text) else { continue }
            let chunkID = "N/B\(i)/0"
            idByChunk[chunkID] = doc.id
            await store.upsert(EmbeddingRecord(ref: BlockRef(noteID: "N", blockID: "B\(i)"),
                                               chunkID: chunkID, contentHash: "h\(i)",
                                               embeddingVersion: provider.modelInfo.version,
                                               dimension: provider.modelInfo.dimension, vector: v))
        }
        let indexed = await store.count()
        r.expect(indexed == corpus.count, "语料全部入索引")

        var hitAt1 = 0, hitAt3 = 0
        var mrr = 0.0
        var lines: [String] = []
        for (q, expected) in queries {
            guard let qv = try? await provider.embed(q) else { continue }
            let hits = await store.search(query: qv, topK: corpus.count)
            let ids = hits.compactMap { idByChunk[$0.chunkID] }
            let rank = ids.firstIndex { expected.contains($0) }
            if let rank {
                if rank == 0 { hitAt1 += 1 }
                if rank < 3 { hitAt3 += 1 }
                mrr += 1.0 / Double(rank + 1)
            }
            lines.append(String(format: "    %-18@ → #%@  top=%@", q as NSString,
                                rank.map { String($0 + 1) } ?? "miss",
                                ids.first ?? "-"))
        }
        let n = Double(queries.count)
        let r1 = Double(hitAt1) / n, r3 = Double(hitAt3) / n, m = mrr / n

        print("\n    ── 真实 embedding 的语义检索（\(corpus.count) 条语料 / \(queries.count) 条 query）──")
        lines.forEach { print($0) }
        print(String(format: "    Recall@1 = %.2f   Recall@3 = %.2f   MRR = %.3f", r1, r3, m))
        print("    注：query 与目标笔记字面几乎不重合，keyword 路对其中多数为零命中\n")

        // 这条断言是 TD-5 的验收线：语义检索必须**真的有效**，
        // 而不只是「管线跑通」。mock provider 在这里必然失败。
        r.expect(r1 >= 0.6, "Recall@1 ≥ 0.6（实测 \(String(format: "%.2f", r1))）—— 语义检索真实有效")
        r.expect(r3 >= 0.8, "Recall@3 ≥ 0.8（实测 \(String(format: "%.2f", r3))）")
        r.expect(m >= 0.6, "MRR ≥ 0.6（实测 \(String(format: "%.3f", m))）")

        // 对照：同样的语料与 query，mock provider 应当**明显更差**。
        // 这是「换上真实模型确有意义」的直接证据。
        let mock = MockEmbeddingProvider(dimension: 640)
        let mockStore = InMemoryVectorStore()
        for (i, doc) in corpus.enumerated() {
            let v = try! await mock.embed(doc.text)
            await mockStore.upsert(EmbeddingRecord(ref: BlockRef(noteID: "N", blockID: "B\(i)"),
                                                   chunkID: "N/B\(i)/0", contentHash: "h",
                                                   embeddingVersion: "mock", dimension: 640, vector: v))
        }
        var mockHit1 = 0
        for (q, expected) in queries {
            let qv = try! await mock.embed(q)
            let hits = await mockStore.search(query: qv, topK: corpus.count)
            let ids = hits.compactMap { idByChunk[$0.chunkID] }
            if let first = ids.first, expected.contains(first) { mockHit1 += 1 }
        }
        let mockR1 = Double(mockHit1) / n
        print(String(format: "    对照：mock provider Recall@1 = %.2f（伪向量，语义邻域无意义）\n", mockR1))
        r.expect(r1 > mockR1, "真实 provider 明显优于 mock（\(String(format: "%.2f vs %.2f", r1, mockR1))）")
    }

    /// 云端 provider 的纯函数部分：请求构造、状态码映射、响应解析。
    /// 不发真实网络请求 —— 这些恰恰是最容易出错且最值得锁住的地方。
    static func runCloud(_ r: CheckRunner) {
        r.suite("TD-5 · 云端 embedding（OpenAI 兼容）")

        // 请求构造
        let req = try? CloudEmbeddingProvider.makeRequest(
            baseURL: "https://api.test.com/v1/", apiKey: "sk-abc",
            model: "text-embedding-3-small", inputs: ["一", "二"])
        r.expect(req?.url?.absoluteString == "https://api.test.com/v1/embeddings",
                 "baseURL 末尾斜杠被规范化（得到 \(req?.url?.absoluteString ?? "nil")）")
        r.expect(req?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-abc", "带上 Bearer token")
        let body = req?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        r.expect((body?["input"] as? [String])?.count == 2, "批量输入放进同一个请求（按请求计费）")

        // 状态码映射：可重试与不可重试必须分开
        func status(_ code: Int) -> EmbeddingProviderError? {
            do { try CloudEmbeddingProvider.mapStatus(code, body: Data()); return nil }
            catch { return error as? EmbeddingProviderError }
        }
        r.expect(status(200) == nil, "2xx 通过")
        r.expect(status(429) == .rateLimited, "429 → rateLimited（可重试）")
        if case .rejected = status(401) { r.expect(true, "401 → rejected（不可重试）") }
        else { r.expect(false, "401 应为 rejected") }
        if case .transport = status(500) { r.expect(true, "5xx → transport（可重试）") }
        else { r.expect(false, "500 应为 transport") }

        // 响应解析：**必须按 index 重排**
        let json = """
        {"data":[{"index":1,"embedding":[0,1,0]},{"index":0,"embedding":[1,0,0]}]}
        """.data(using: .utf8)!
        let parsed = try? CloudEmbeddingProvider.parse(json, expectedCount: 2, dimension: 3)
        r.expect(parsed?.count == 2, "解析出两条")
        r.expect(parsed?[0] == [1, 0, 0], "按 index 重排 —— 服务端不保证顺序，错乱会静默地让向量与文本对不上")

        // 条数不符 / 维度不符都必须失败，而不是写进索引
        let short = """
        {"data":[{"index":0,"embedding":[1,0,0]}]}
        """.data(using: .utf8)!
        r.expect((try? CloudEmbeddingProvider.parse(short, expectedCount: 2, dimension: 3)) == nil,
                 "返回条数不符 → 失败")
        r.expect((try? CloudEmbeddingProvider.parse(json, expectedCount: 2, dimension: 1536)) == nil,
                 "维度不符 → 失败（宁可失败也不能混进不可比的向量）")
        r.expect((try? CloudEmbeddingProvider.parse(Data("not json".utf8), expectedCount: 1, dimension: 3)) == nil,
                 "非法 JSON → 失败")

        // usage.prompt_tokens —— 成本一项要写 measured 就得拿服务端自己报的数
        let withUsage = """
        {"data":[{"index":0,"embedding":[1,0,0]}],"usage":{"prompt_tokens":42,"total_tokens":42}}
        """.data(using: .utf8)!
        r.expect(CloudEmbeddingProvider.parseUsage(withUsage) == 42,
                 "解析出服务端回报的 prompt_tokens —— 成本口径是 token，字符数只是代理量")
        r.expect(CloudEmbeddingProvider.parseUsage(json) == nil,
                 "服务端没回报 usage → nil，**不是 0** —— 0 会把成本算成免费")
        r.expect((try? CloudEmbeddingProvider.parse(withUsage, expectedCount: 1, dimension: 3))?.count == 1,
                 "带 usage 的响应照常解析出向量")
        let usageOnlyTotal = """
        {"data":[],"usage":{"total_tokens":7}}
        """.data(using: .utf8)!
        r.expect(CloudEmbeddingProvider.parseUsage(usageOnlyTotal) == 7,
                 "只报 total_tokens 的服务端也要能取到（回退，不是猜）")
        r.expect(CloudEmbeddingProvider.parseUsage(Data("not json".utf8)) == nil,
                 "usage 解析失败不抛错 —— 它不该让一批已经拿到的向量作废")
    }
}
