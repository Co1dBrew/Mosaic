import Foundation
import SwiftData
import Observation
import MosaicKit

/// # TD-8 —— 生产索引服务
///
/// 在此之前，`Sources/MosaicKit/Retrieval/` 里的每一块都单独测过，但**没有人把它们
/// 接起来**：derived store 只有测试在写，所以真机上 `rebuildIndexFromStore()` 永远
/// 读到 0 条，Retrieval Lab 的 vector 路一直是空的。这个类就是那条缺失的接线。
///
/// ## 管线
///
/// ```
/// 笔记内容 ──▶ OCR（图片块，derived）
///          ──▶ DerivedWorkScanner.plan   ← 与已存记录比对，得出 pending / orphan
///          ──▶ AIJobCoordinator          ← 并发上限 · 按 contentHash 去重 · 重试
///          ──▶ provider.embed            ← off-main
///          ──▶ DerivedDataStore.commit   ← StaleGuard 校验，同步 @MainActor 临界区
///          ──▶ InMemoryVectorStore       ← **只有被接受的记录才进内存索引**
/// ```
///
/// ## 三条不变量
///
/// 1. **内存索引只装落盘成功的向量。** `commitBatch` 逐条校验，被 `StaleGuard` 拒掉的
///    那条**不能**进内存索引 —— 否则磁盘上没有的过期向量会继续参与线上检索，
///    而这正是 stale protection 要防的事，只是换了个地方发生。
/// 2. **orphan 先删再写。** 块被删、被清空、或从 N 个 chunk 缩到更少时，
///    旧 chunk 必须立刻停止可被检索；留到下一轮意味着搜到一段已经不存在的文本。
/// 3. **不靠取消保证正确性。** 编辑过程中不断有新的扫描进来，旧任务照跑；
///    去重靠 `EmbeddingJobKey`（含 contentHash），正确性靠写入路径的校验
///    （`RETRIEVAL_ARCHITECTURE.md` §4）。
@Observable
@MainActor
final class IndexingService {

    /// 索引口径的唯一来源：chunk 策略与 embedding 版本都从这里取。
    /// 生产索引必须只有**一套**策略 —— 两套策略的记录混在一个 store 里，
    /// chunkID 对不上，vector 命中会被静默丢弃。
    ///
    /// 只能由 `applyConfig` 改，而它的唯一调用方是 Release Gate 的 Promote
    /// （backlog 5.1：生产配置只能经 Promote 更换）。
    private(set) var config: RetrievalConfig

    private(set) var state: IndexState = .ready
    private(set) var indexedChunks = 0
    private(set) var pendingChunks = 0
    /// 上一次失败原因（provider 不可用 / 嵌入报错）。静默失败会让索引看起来是空的。
    private(set) var lastError: String?

    /// 当前这条索引在用的 provider。换 provider = 换向量空间，必须重建。
    private(set) var provider: (any EmbeddingProvider)?
    private let vectors: InMemoryVectorStore
    private let derived: DerivedDataStore
    private let extractor: (any ImageTextExtractor)?
    private let noteContext: ModelContext
    private let coordinator: AIJobCoordinator<[Float]>
    private let debounceNanos: UInt64

    /// 每篇笔记上一次扫描的规模，用来算全局状态而不必每次重扫全库。
    private var scanned: [String: (total: Int, pending: Int)] = [:]
    private var dirtyNoteIDs: Set<String> = []
    private var flushTask: Task<Void, Never>?

    init(provider: (any EmbeddingProvider)?,
         vectors: InMemoryVectorStore,
         derived: DerivedDataStore,
         noteContext: ModelContext,
         extractor: (any ImageTextExtractor)? = nil,
         config: RetrievalConfig = .production,
         maxConcurrent: Int = 2,
         debounceNanos: UInt64 = 600_000_000) {
        self.provider = provider
        self.vectors = vectors
        self.derived = derived
        self.noteContext = noteContext
        self.extractor = extractor
        self.config = config
        self.coordinator = AIJobCoordinator(policy: .init(maxConcurrent: maxConcurrent))
        self.debounceNanos = debounceNanos
    }

    var embeddingVersion: String { provider?.modelInfo.version ?? "unavailable" }
    var isAvailable: Bool { provider != nil }

    // MARK: 触发入口

    /// 启动时：先把落盘的向量灌回内存，再补齐缺的。
    ///
    /// 顺序不能反 —— 先扫描会把「其实已经存好、只是还没加载」的 chunk 判成 pending，
    /// 于是每次冷启动都重嵌一遍全库。
    func start() async {
        await loadPersistedIndex()
        // 历史孤儿：这台设备上**在修复之前**删掉的文件夹留下的 derived 数据。
        // 只修未来的删除路径不够 —— 那些记录已经在磁盘上，而且每次冷启动都会被
        // `loadPersistedIndex` 忠实地灌回内存索引，继续占 topK 名额。
        _ = await reconcileOrphans()
        await indexAll()
    }

    /// 把 derived store 里的向量灌进内存索引。索引没有构建步骤，
    /// 所以它不可能相对来源过期（`RETRIEVAL_ARCHITECTURE.md` §9.6）。
    func loadPersistedIndex() async {
        // 只灌回**当前** embedding 版本的记录。换过 provider 的旧向量
        // 维度不同，留在内存里会污染检索。
        let version = embeddingVersion
        let matching = derived.allRecords().filter { $0.embeddingVersion == version }
        await vectors.removeAll()
        await vectors.upsert(matching)
        indexedChunks = await vectors.count()
    }

    /// 只换引用，不重建。启动时在 `loadPersistedIndex` 之前调用。
    func adoptProvider(_ new: (any EmbeddingProvider)?, unavailableReason: String? = nil) {
        provider = new
        if provider == nil {
            lastError = unavailableReason ?? lastError
        } else if lastError?.contains("中文") == true || lastError?.contains("句向量") == true {
            lastError = nil
        }
    }

    /// 换 embedding 路线（中文云端 / 英文本地）。版本没变则只刷新状态。
    func applyProvider(_ new: (any EmbeddingProvider)?, unavailableReason: String? = nil) async {
        let changed = new?.modelInfo.version != provider?.modelInfo.version
        adoptProvider(new, unavailableReason: unavailableReason)
        guard changed else { await refreshState(); return }
        scanned.removeAll()
        await vectors.removeAll()
        await indexAll()
    }

    func fetchCards() -> [Card] {
        allCards()
    }

    /// 单篇查找。编辑路径上的路线判定只看被改的那一篇，不扫全库。
    func card(withID id: String) -> Card? {
        card(id: id)
    }

    /// Promote 之后换用新的生产配置（backlog 5.4）。
    ///
    /// 换了 chunk 策略就必须重建索引：旧记录的 chunkID 是按旧策略算的，
    /// 留着它们等于让两套策略的记录混在一个 store 里 —— vector 命中会被静默丢弃，
    /// 表现成「上线之后语义突然变差」，而真正原因是索引对不上（§15.3）。
    ///
    /// **先删后扫**，顺序与启动时相反：这里的旧记录是**确定**无效的，
    /// 不是「可能还没加载」。
    func applyConfig(_ new: RetrievalConfig) async {
        let strategyChanged = new.chunkStrategy.identity != config.chunkStrategy.identity
        config = new
        guard strategyChanged else { await refreshState(); return }
        // 全库 chunk 身份全变 —— `DerivedWorkScanner` 会把旧记录判成 orphan，
        // 所以这里只要重扫一遍，删除与重嵌都在 `index(card:)` 里发生。
        scanned.removeAll()
        await indexAll()
    }

    /// 全库扫描。启动时跑一次，之后只在明确要求时跑（Developer Mode 的 Rescan）。
    func indexAll() async {
        await index(noteIDs: allCards().map { $0.id.uuidString })
    }

    /// 一次编辑之后调用。**合并 + 防抖**：自动保存会在一次输入里触发很多次，
    /// 每次都立刻扫描等于把 CPU 花在同一篇笔记上。
    func noteDidChange(_ noteID: String) {
        dirtyNoteIDs.insert(noteID)
        flushTask?.cancel()
        flushTask = Task { @MainActor [debounceNanos] in
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            let ids = dirtyNoteIDs
            dirtyNoteIDs.removeAll()
            await index(noteIDs: Array(ids))
        }
    }

    /// 笔记被删除。derived 数据必须跟着走 —— 否则搜索会命中一篇已经不存在的笔记，
    /// 点进去是空的。
    func noteWasDeleted(_ noteID: String) async {
        let chunkIDs = derived.chunkIDs(noteID: noteID)
        derived.deleteChunks(chunkIDs)
        derived.deleteOCR(noteID: noteID)
        await vectors.removeNote(noteID)
        scanned.removeValue(forKey: noteID)
        dirtyNoteIDs.remove(noteID)
        await refreshState()
    }

    /// 一批笔记被删除（删文件夹会一次删掉其中全部笔记）。
    ///
    /// **不是 `for id in ids { await noteWasDeleted(id) }` 的语法糖**：那样每篇都会
    /// 走一次 `refreshState()`，删 200 篇就重算 200 次状态。这里只在末尾算一次。
    func notesWereDeleted(_ noteIDs: [String]) async {
        guard !noteIDs.isEmpty else { return }
        for noteID in noteIDs {
            derived.deleteChunks(derived.chunkIDs(noteID: noteID))
            derived.deleteOCR(noteID: noteID)
            await vectors.removeNote(noteID)
            scanned.removeValue(forKey: noteID)
            dirtyNoteIDs.remove(noteID)
        }
        await refreshState()
    }

    // MARK: 一致性对账

    /// 只查不改。Developer Tools 的「Derived 一致性」一行读它，测试也读它。
    func consistencyReport() async -> DerivedConsistencyReport {
        DerivedConsistency.check(liveNoteIDs: Set(allCards().map { $0.id.uuidString }),
                                 embeddingNoteIDs: derived.embeddingNoteIDs(),
                                 ocrNoteIDs: derived.ocrNoteIDs(),
                                 indexedNoteIDs: await vectors.noteIDs())
    }

    /// 查完就清。返回的是**清理前**的报告 —— 调用方要知道清掉了什么，
    /// 而清理后的报告永远是「一致」，说明不了任何事。
    ///
    /// 空笔记库时拒绝执行（`DerivedConsistency.isSafeToReconcile`）：那更可能是一次
    /// 读取失败，而猜错方向的代价是把一份要几分钟才能重建的索引删掉。
    @discardableResult
    func reconcileOrphans() async -> DerivedConsistencyReport {
        let report = await consistencyReport()
        guard !report.isConsistent, DerivedConsistency.isSafeToReconcile(report) else { return report }
        await notesWereDeleted(report.orphanNoteIDs)
        return report
    }

    // MARK: 主流程

    func index(noteIDs: [String]) async {
        guard !noteIDs.isEmpty else { await refreshState(); return }
        for noteID in noteIDs {
            guard let card = card(id: noteID) else {
                // 扫描期间笔记被删了 —— 按删除处理，别留下孤儿向量。
                await noteWasDeleted(noteID)
                continue
            }
            await index(card: card)
        }
        await refreshState()
    }

    private func index(card: Card) async {
        let noteID = card.id.uuidString

        // 1 · OCR 先行：图片块的可检索文本来自它，缺了就等于这个块没有内容。
        await extractMissingOCR(card: card)
        let ocr = derived.ocrTextByBlockID(noteID: noteID)

        // 2 · 与已存记录比对
        let plan = DerivedWorkScanner.plan(noteID: noteID,
                                           blocks: card.blockContents(),
                                           strategy: config.chunkStrategy,
                                           existingRecords: derived.existingRecords(noteID: noteID),
                                           embeddingVersion: embeddingVersion,
                                           ocrTextByBlockID: ocr)

        // 3 · orphan 先删。不变量 2。
        if !plan.orphanChunkIDs.isEmpty {
            derived.deleteChunks(plan.orphanChunkIDs)
            await vectors.removeChunks(plan.orphanChunkIDs)
        }

        guard let provider, !plan.pending.isEmpty else {
            scanned[noteID] = (plan.totalChunks, provider == nil ? plan.pending.count : 0)
            return
        }

        // 4 · 嵌入。经 coordinator：并发上限 + 按 contentHash 去重 + 可重试错误重试。
        var produced: [(item: DerivedWorkItem, vector: [Float])] = []
        var failed = 0
        for item in plan.pending {
            let text = item.text
            let task = await coordinator.submit(item.key) { try await provider.embed(text) }
            do { produced.append((item, try await task.value)) }
            catch is CancellationError { failed += 1 }
            catch {
                failed += 1
                lastError = String(describing: error)
            }
        }

        // 5 · 落盘（逐条 StaleGuard 校验）→ 只把**被接受**的写进内存索引。不变量 1。
        let batch = produced.map {
            (result: DerivedResult(key: $0.item.key, payload: $0.vector),
             chunkID: $0.item.chunkID,
             chunkIndex: $0.item.key.chunkIndex,
             strategy: config.chunkStrategy.identity)
        }
        let decisions = derived.commitBatch(batch,
                                            embeddingVersion: embeddingVersion,
                                            noteContext: noteContext,
                                            ocrTextByBlockID: ocr)

        var rejected = 0
        for (entry, decision) in zip(produced, decisions) {
            guard decision.isAccepted else { rejected += 1; continue }
            await vectors.upsert(EmbeddingRecord(ref: entry.item.key.ref,
                                                 chunkID: entry.item.chunkID,
                                                 chunkIndex: entry.item.key.chunkIndex,
                                                 contentHash: entry.item.key.contentHash,
                                                 embeddingVersion: embeddingVersion,
                                                 chunkStrategy: config.chunkStrategy.identity,
                                                 dimension: entry.vector.count,
                                                 vector: entry.vector))
        }

        // 被拒的那条是因为内容在嵌入期间又变了 —— 那次编辑自己会触发新一轮扫描，
        // 这里只如实记下「还欠多少」。
        scanned[noteID] = (plan.totalChunks, failed + rejected)
    }

    /// 给还没有当前 OCR 的图片块做识别。
    ///
    /// OCR 按**块内容哈希**存（哈希里已经含图片资源路径），所以换了图片旧 OCR 自动失效。
    /// 识别失败只记不抛：一张读不出字的照片不该挡住整篇笔记的索引。
    private func extractMissingOCR(card: Card) async {
        guard let extractor else { return }
        let noteID = card.id.uuidString
        for block in card.orderedBlocks where block.kind == .image {
            let path = block.imageRelativePath
            guard !path.isEmpty else { continue }
            let ref = BlockRef(noteID: noteID, blockID: block.id.uuidString)
            let hash = AIContentHash.forBlock(block.toContent())
            guard derived.ocrText(for: ref, currentContentHashIgnoringOCR: hash) == nil else { continue }
            do {
                let result = try await extractor.extractText(fromRelativePath: path)
                guard !result.text.isEmpty else { continue }
                derived.saveOCR(ImageTextExtraction(ref: ref, contentHash: hash,
                                                    text: result.text, confidence: result.confidence),
                                engineIdentifier: extractor.engineIdentifier)
            } catch {
                lastError = String(describing: error)
            }
        }
    }

    // MARK: 状态

    /// 索引状态由**事实**推导，不是由某处 set 出来的 —— 可 set 的状态字段会卡住
    /// （`IndexState.swift`）。
    func refreshState() async {
        indexedChunks = await vectors.count()
        let total = scanned.values.reduce(0) { $0 + $1.total }
        pendingChunks = scanned.values.reduce(0) { $0 + $1.pending }
        state = IndexStateMachine.derive(totalChunks: total,
                                         pendingChunks: pendingChunks,
                                         runningJobs: await coordinator.inFlightCount,
                                         hasEmbeddings: indexedChunks > 0,
                                         failure: provider == nil
                                             ? (lastError ?? "语义检索不可用；关键词搜索不受影响")
                                             : lastError)
    }

    // MARK: SwiftData 读取

    private func allCards() -> [Card] {
        (try? noteContext.fetch(FetchDescriptor<Card>())) ?? []
    }

    private func card(id: String) -> Card? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var fetch = FetchDescriptor<Card>(predicate: #Predicate { $0.id == uuid })
        fetch.fetchLimit = 1
        return (try? noteContext.fetch(fetch))?.first
    }
}
