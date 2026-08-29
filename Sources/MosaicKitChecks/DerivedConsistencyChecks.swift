import Foundation
import MosaicKit

/// Derived 数据一致性对账的口径断言。
///
/// 这里只测**定义**：哪些算孤儿、空库时能不能执行清理。真正的接线
/// （删文件夹 / 删笔记 / 重启后仍然干净 / 搜索不再吃到孤儿）需要 SwiftData，
/// 在 `MosaicTests/DerivedCleanupTests.swift` 里，跑在模拟器上。
enum DerivedConsistencyChecks {

    static func run(_ r: CheckRunner) {
        checkDefinition(r)
        checkThreeSourcesAreIndependent(r)
        checkEmptyCorpusIsNotReconcilable(r)
    }

    static func runRetrieval(_ r: CheckRunner) async {
        await checkStaleIndexEntryDoesNotConsumeATopKSlot(r)
    }

    // MARK: 4 · 索引里有、语料里没有的 chunk 不能吃掉一个名额

    /// 删除通知是异步的，索引重建也要时间 —— 「索引里有、语料里已经没有」的窗口
    /// 一定存在。老实现 `fused.prefix(topK)` 会让那条陈旧记录占掉一格再被跳过，
    /// 于是结果**少一条**，而少的那一条没有任何迹象。
    ///
    /// 两条断言缺一不可：
    /// 1. 有孤儿时结果仍然是满的（这是修复）。
    /// 2. 没有孤儿时结果**逐位不变**（这是修复没有偷偷改排序的证明）。
    private static func checkStaleIndexEntryDoesNotConsumeATopKSlot(_ r: CheckRunner) async {
        r.suite("检索 · 索引里的陈旧 chunk 被跳过后继续往下取，不占 topK 名额")

        let provider = MockEmbeddingProvider(dimension: 16)
        let topK = 5
        let config = RetrievalConfig(version: "stale-slot", mode: .hybrid,
                                     embeddingProvider: "mock", embeddingVersion: "mock-v1",
                                     chunkStrategy: .block, topK: topK)

        // 八篇互相竞争的笔记 —— 相似是必需的，否则「少一条」看不出来。
        var chunks: [NoteChunk] = []
        for i in 0..<8 {
            let block = CardBlockContent(id: "b\(i)", order: 0, kind: .text,
                                         text: "第 \(i) 版排期：搜索 beta 的交付时间与验收安排。")
            chunks += ChunkPipeline.chunks(noteID: "n\(i)", blocks: [block], strategy: .block)
        }

        func indexed(_ chunks: [NoteChunk]) async -> InMemoryVectorStore {
            let store = InMemoryVectorStore()
            for c in chunks {
                let v = MockEmbeddingProvider.deterministicVector(for: c.text, dimension: 16)
                await store.upsert(EmbeddingRecord(ref: c.ref, chunkID: c.id, chunkIndex: 0,
                                                   contentHash: c.contentHash,
                                                   embeddingVersion: "mock-v1",
                                                   chunkStrategy: ChunkStrategy.block.identity,
                                                   dimension: 16, vector: v))
            }
            return store
        }

        // 基准：索引与语料完全一致。
        let cleanStore = await indexed(chunks)
        let cleanService = RetrievalService(provider: provider, vectors: cleanStore)
        let clean = await cleanService.retrieve(query: "排期 交付 验收", chunks: chunks, config: config)
        r.expectEqual(clean.results.count, topK, "基准：topK 满")

        // 前三篇从语料里消失，但索引还没清 —— 删除刚发生的那个窗口。
        let survivors = chunks.filter { !["n0", "n1", "n2"].contains($0.ref.noteID) }
        let stale = await cleanService.retrieve(query: "排期 交付 验收", chunks: survivors, config: config)
        r.expectEqual(stale.results.count, topK,
                      "有陈旧索引项时 topK 仍然是满的 —— 老写法这里会少给 1–3 条")
        r.expect(stale.results.allSatisfy { !["n0", "n1", "n2"].contains($0.ref.noteID) },
                 "陈旧项本身不出现在结果里")
        r.expect(stale.results.map(\.fusedRank) == Array(1...topK),
                 "名次连续 —— 跳过一条不该在排名上留一个洞")

        // 没有孤儿时必须逐位不变：修复不能顺带改了排序。
        let survivorStore = await indexed(survivors)
        let survivorService = RetrievalService(provider: provider, vectors: survivorStore)
        let reference = await survivorService.retrieve(query: "排期 交付 验收",
                                                       chunks: survivors, config: config)
        r.expectEqual(stale.results.map(\.chunkID), reference.results.map(\.chunkID),
                      "跳过陈旧项之后的排序，与一开始就没有这些记录时**完全相同**")
    }

    // MARK: 1 · 孤儿的定义

    private static func checkDefinition(_ r: CheckRunner) {
        r.suite("Derived 对账 · 孤儿 = derived 引用了、但笔记库里已经没有的 noteID")

        let live: Set<String> = ["n1", "n2"]
        let clean = DerivedConsistency.check(liveNoteIDs: live,
                                             embeddingNoteIDs: ["n1", "n2"],
                                             ocrNoteIDs: ["n1"],
                                             indexedNoteIDs: ["n1", "n2"])
        r.expect(clean.isConsistent, "全部引用都指向活着的笔记 → 一致")
        r.expectEqual(clean.orphanNoteIDs, [], "一致时孤儿清单为空")
        r.expect(clean.summary.contains("无孤儿"), "一致时的说明要能直接摆进 Developer Tools")

        // derived 是笔记的**子集**才正常：有笔记还没索引不是错误（pending），
        // 有索引却没有笔记才是。这两个方向不能混。
        let notYetIndexed = DerivedConsistency.check(liveNoteIDs: ["n1", "n2", "n3"],
                                                     embeddingNoteIDs: ["n1"],
                                                     ocrNoteIDs: [],
                                                     indexedNoteIDs: ["n1"])
        r.expect(notYetIndexed.isConsistent,
                 "笔记多于 derived = 还没索引完，**不是**不一致 —— 判成不一致会让每台新设备一开机就报错")

        let leaked = DerivedConsistency.check(liveNoteIDs: ["n1"],
                                              embeddingNoteIDs: ["n1", "gone"],
                                              ocrNoteIDs: [],
                                              indexedNoteIDs: ["n1", "gone"])
        r.expect(!leaked.isConsistent, "笔记已删但 embedding 还在 → 不一致")
        r.expectEqual(leaked.orphanNoteIDs, ["gone"], "孤儿清单按笔记去重后给出")
        r.expect(leaked.summary.contains("孤儿"), "不一致时说明要点出是哪几处")
    }

    // MARK: 2 · 三个来源各自可以走偏

    private static func checkThreeSourcesAreIndependent(_ r: CheckRunner) {
        r.suite("Derived 对账 · embedding / OCR / 内存索引 三处分别检查")

        // 只有 OCR 漏了。这一种最隐蔽：它不直接进检索，但下一次重新索引时会被当作
        // 有效 overlay 拼进 chunk 文本 —— 一段属于已删除笔记的文字会重新变得可检索。
        let ocrOnly = DerivedConsistency.check(liveNoteIDs: ["n1"],
                                               embeddingNoteIDs: ["n1"],
                                               ocrNoteIDs: ["n1", "gone"],
                                               indexedNoteIDs: ["n1"])
        r.expect(!ocrOnly.isConsistent, "OCR 单独漏掉也算不一致")
        r.expectEqual(ocrOnly.orphanOCRNoteIDs, ["gone"], "OCR 孤儿单独可见")
        r.expectEqual(ocrOnly.orphanEmbeddingNoteIDs, [], "不把 OCR 的问题记到 embedding 头上")

        // 只有内存索引漏了：磁盘清干净了，但这次运行里的索引还留着。
        // 表现是「重启后搜索正常，重启前不正常」——最容易被当成偶发问题放过。
        let memoryOnly = DerivedConsistency.check(liveNoteIDs: ["n1"],
                                                  embeddingNoteIDs: ["n1"],
                                                  ocrNoteIDs: ["n1"],
                                                  indexedNoteIDs: ["n1", "gone"])
        r.expect(!memoryOnly.isConsistent, "内存索引单独漏掉也算不一致")
        r.expectEqual(memoryOnly.orphanIndexedNoteIDs, ["gone"], "内存索引孤儿单独可见")

        let all = DerivedConsistency.check(liveNoteIDs: [],
                                           embeddingNoteIDs: ["a"],
                                           ocrNoteIDs: ["b"],
                                           indexedNoteIDs: ["c"])
        r.expectEqual(all.orphanNoteIDs, ["a", "b", "c"], "并集覆盖三个来源，且排序稳定")
    }

    // MARK: 3 · 空库时不执行清理

    private static func checkEmptyCorpusIsNotReconcilable(_ r: CheckRunner) {
        r.suite("Derived 对账 · 空笔记库时只报告不清理（读取失败与真的删光了不可区分）")

        let suspicious = DerivedConsistency.check(liveNoteIDs: [],
                                                  embeddingNoteIDs: ["n1", "n2"],
                                                  ocrNoteIDs: [],
                                                  indexedNoteIDs: ["n1", "n2"])
        r.expect(!suspicious.isConsistent, "空库 + 有 derived 数据 → 报告为不一致")
        r.expect(!DerivedConsistency.isSafeToReconcile(suspicious),
                 "但**不允许**据此删除 —— 这更可能是笔记库这次没读出来，而猜错方向要重建整个索引（云端还要花钱）")

        let empty = DerivedConsistency.check(liveNoteIDs: [], embeddingNoteIDs: [],
                                             ocrNoteIDs: [], indexedNoteIDs: [])
        r.expect(DerivedConsistency.isSafeToReconcile(empty),
                 "真正的空状态（两边都空）不该被否决 —— 否则新装的 App 每次启动都在报警")

        let normal = DerivedConsistency.check(liveNoteIDs: ["n1"],
                                              embeddingNoteIDs: ["n1", "gone"],
                                              ocrNoteIDs: [],
                                              indexedNoteIDs: ["n1"])
        r.expect(DerivedConsistency.isSafeToReconcile(normal),
                 "库里还有笔记时，孤儿清理照常执行")
    }
}
