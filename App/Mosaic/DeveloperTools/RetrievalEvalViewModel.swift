import Foundation
import SwiftData
import Observation
import MosaicKit

/// # D5 / D6 —— Eval Center 与 Config Comparison 的 ViewModel
///
/// 职责四件事（`DEVTOOLS_SWIFTUI_PLAN.md` §3）：驱动 `EvalRunner`、回报进度、
/// 与 baseline 求 delta、收集失败用例。
///
/// **不做判定。** 「这套配置能不能上线」是 Release Gate 的事（Week 5）；
/// 这里最多给一句 trade-off。把判定放进 Eval 会出现两个地方都能说 PASS。
@Observable
@MainActor
final class RetrievalEvalViewModel {

    enum Phase: Equatable {
        case idle
        /// 已经点了 Run，但异步任务还没跑起来。**在 `run()` 里同步进入**，
        /// 否则按钮会在一个 runloop 里仍然可点，连点两次就是两批并发的跑批。
        case preparing
        /// 评测用的向量索引正在建立。与 `running` 分开，因为它不计入延迟指标。
        case indexing(done: Int, total: Int)
        case running(done: Int, total: Int)
        case done
        case failed(String)
    }

    // MARK: 输入 —— candidate

    var selection: EvalDataset.Selection = .both
    var mode: RetrievalMode = .hybrid
    var chunkStrategy: ChunkStrategy = .default
    var topK: Int = 20
    var fusion: FusionMethod = .default

    // MARK: 输入 —— baseline（D6）

    var baselineMode: RetrievalMode = .keyword
    var baselineChunkStrategy: ChunkStrategy = .default
    var baselineTopK: Int = 20
    var baselineFusion: FusionMethod = .default

    // MARK: 输出

    private(set) var phase: Phase = .idle
    private(set) var run: EvalRun?
    private(set) var baselineRun: EvalRun?
    /// 失败用例的**可标注副本**。归因是本次会话内的工作状态，只有在
    /// `Add to Regression Set` 时才随用例落盘（`DEVTOOLS.md` §5.3）。
    private(set) var failures: [EvalFailure] = []

    let store: EvalDatasetStore
    /// 供 Golden Set 标注时列出笔记，以及把 noteID 还原成标题。
    let corpus: NoteCorpus
    /// 当前这次跑批用的**用例快照**。baseline 必须跑同一批 ——
    /// 否则 D6 的 delta 里混进了「用例集变了」，那不是配置的差异。
    /// 这不是假想：D9 的 `Add to Regression Set` 会当场把 `.both` 的用例数 +1。
    private(set) var evaluatedCases: [EvalCase] = []
    private let provider: (any EmbeddingProvider)?
    /// 跑批结果的去处。**Gate 不自己跑评测** —— 两处各自跑出来的数字，
    /// 迟早会出现「Eval 里是 0.875、Gate 里是 0.861」这种没人能解释的差异。
    private let release: ReleaseStore?
    private var runTask: Task<Void, Never>?
    /// 索引缓存：同一份语料 + 同一套策略不重复嵌入。
    private var cachedIndexKey: String?
    private var cachedIndex: InMemoryVectorStore?

    init(store: EvalDatasetStore,
         provider: (any EmbeddingProvider)?,
         corpus: NoteCorpus,
         release: ReleaseStore? = nil) {
        self.store = store
        self.provider = provider
        self.corpus = corpus
        self.release = release
        if let release {
            // 默认对着**要判定的那套配置**跑 —— 不然 Gate 永远 STALE，
            // 而人会以为是 Gate 坏了。
            let target = release.evaluationTarget.config
            self.mode = target.mode
            self.chunkStrategy = target.chunkStrategy
            self.topK = target.topK
            self.fusion = target.fusion
        }
    }

    // MARK: 配置

    var config: RetrievalConfig { makeConfig(mode: mode, strategy: chunkStrategy, topK: topK, fusion: fusion) }
    var baselineConfig: RetrievalConfig {
        makeConfig(mode: baselineMode, strategy: baselineChunkStrategy,
                   topK: baselineTopK, fusion: baselineFusion)
    }

    /// `version` 优先取**注册表里参数完全一致的那条记录**的版本号（5.1）；
    /// 没有对应记录时退回由可调项拼出来的描述串。
    ///
    /// 这个区分是 Gate 判定的关键：随手在 Eval 里调一个 topK 跑出来的结果，
    /// 版本号是 `hybrid/block/k35/...`，与候选配置的 `retrieval-v3` 对不上，
    /// Gate 会如实报 **STALE** 而不是拿它放行 —— 那正是「改完参数没重跑评测就上线」
    /// 要被拦住的形态。
    private func makeConfig(mode: RetrievalMode, strategy: ChunkStrategy,
                            topK: Int, fusion: FusionMethod) -> RetrievalConfig {
        let descriptive = "\(mode.rawValue)/\(strategy.identity)/k\(topK)/\(fusion.description)"
        let matched = release?.registry.records.first {
            $0.config.mode == mode && $0.config.chunkStrategy == strategy
                && $0.config.topK == topK && $0.config.fusion == fusion
        }
        return RetrievalConfig(version: matched?.config.version ?? descriptive,
                        mode: mode,
                        embeddingProvider: provider?.modelInfo.identifier ?? "unavailable",
                        embeddingVersion: provider?.modelInfo.version ?? "unavailable",
                        chunkStrategy: strategy,
                        topK: topK,
                        fusion: fusion)
    }

    var providerAvailable: Bool { provider != nil }
    var caseCount: Int { store.count(selection) }

    /// 引用了已删除笔记的用例 —— 它们必然失败，但原因不是检索质量。
    var danglingCases: [EvalCase] {
        EvalDataset.danglingCases(store.cases(selection), existingNoteIDs: corpus.existingNoteIDs())
    }

    var isBusy: Bool {
        switch phase {
        case .preparing, .indexing, .running: return true
        default: return false
        }
    }

    // MARK: D6 —— 对比

    /// 两次跑批是否跑在同一批用例上。不同则 delta 无意义，宁可不显示。
    var isComparable: Bool {
        guard let run, let baselineRun else { return false }
        return run.metrics.caseCount == baselineRun.metrics.caseCount
    }

    var deltas: [MetricDelta] {
        guard let run, let baselineRun, isComparable else { return [] }
        return EvalComparison.compare(current: run.metrics, baseline: baselineRun.metrics)
    }

    var tradeoffSummary: String? {
        let d = deltas
        return d.isEmpty ? nil : EvalComparison.tradeoffSummary(d)
    }

    // MARK: 执行

    func run(baseline: Bool = false) {
        runTask?.cancel()
        // baseline 跑 current 当时的那一批用例，不重新取数据集。
        let cases = baseline ? evaluatedCases : store.cases(selection)
        guard !cases.isEmpty else {
            phase = .failed("数据集为空 —— 先在 Dataset 里加用例。空集合跑出来的 0.000 不是「质量差」，是没有测。")
            return
        }
        let config = baseline ? baselineConfig : self.config
        guard config.mode == .keyword || providerAvailable else {
            phase = .failed("本机没有可用的本地句向量模型，语义路无法评测。Mode 选 Keyword 仍可跑。")
            return
        }

        phase = .preparing
        runTask = Task { @MainActor in
            do {
                let result = try await execute(cases: cases, config: config)
                guard !Task.isCancelled else { return }
                if baseline {
                    baselineRun = result
                    release?.recordBaselineRun(result)
                } else {
                    run = result
                    failures = result.failures
                    evaluatedCases = cases
                    // 换了 current 就没有可比的 baseline 了 —— 留着旧的会让人拿
                    // 新 current 去比一份跑在别的用例 / 别的时间点上的 baseline。
                    baselineRun = nil
                    release?.recordRun(result)
                }
                phase = .done
            } catch is CancellationError {
                // 取消不留半份结果（`EvalRunner` 的口径）：半份指标比没有指标更危险。
                phase = .idle
            } catch {
                phase = .failed(String(describing: error))
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        phase = .idle
    }

    private func execute(cases: [EvalCase], config: RetrievalConfig) async throws -> EvalRun {
        let chunks = corpus.chunks(strategy: config.chunkStrategy)
        guard !chunks.isEmpty else {
            throw EvalError.message("语料为空 —— 一条笔记都没有可检索文本。")
        }

        let vectors: InMemoryVectorStore
        if config.mode == .keyword {
            vectors = InMemoryVectorStore()
        } else {
            vectors = try await index(for: chunks, config: config)
        }

        let service = RetrievalService(provider: config.mode == .keyword ? nil : provider,
                                       vectors: vectors)
        let runner = EvalRunner(service: service, chunksProvider: { chunks })
        phase = .running(done: 0, total: cases.count)

        return try await runner.run(cases: cases, config: config) { [weak self] progress in
            Task { @MainActor in
                guard let self, self.isBusy else { return }
                self.phase = .running(done: progress.done, total: progress.total)
            }
        }
    }

    /// 为本次评测建一份**独立**的内存索引。
    ///
    /// 为什么不用生产索引：生产索引是用某一套 chunk 策略建的，换策略后 chunkID 全变，
    /// vector 路命中的 chunk 在当前语料里找不到，会被静默丢弃 —— 结果是「换了策略
    /// 语义路突然变差」，而真正的原因是索引对不上。评测必须在与语料一致的索引上跑。
    ///
    /// **不落盘**：评测索引不进 derived store，也不覆盖生产索引。
    private func index(for chunks: [NoteChunk], config: RetrievalConfig) async throws -> InMemoryVectorStore {
        guard let provider else { throw EvalError.message("没有可用的句向量模型。") }

        var hasher = Hasher()
        hasher.combine(provider.modelInfo.version)
        hasher.combine(config.chunkStrategy.identity)
        for c in chunks { hasher.combine(c.id); hasher.combine(c.contentHash) }
        let key = "\(hasher.finalize())"
        if key == cachedIndexKey, let cachedIndex { return cachedIndex }

        let store = InMemoryVectorStore()
        let batchSize = 32
        phase = .indexing(done: 0, total: chunks.count)

        var done = 0
        for start in stride(from: 0, to: chunks.count, by: batchSize) {
            try Task.checkCancellation()
            let batch = Array(chunks[start..<min(start + batchSize, chunks.count)])
            let vectors = try await provider.embed(batch: batch.map(\.text))
            for (chunk, vector) in zip(batch, vectors) {
                await store.upsert(EmbeddingRecord(ref: chunk.ref, chunkID: chunk.id,
                                                   chunkIndex: chunk.indexInBlock,
                                                   contentHash: chunk.contentHash,
                                                   embeddingVersion: provider.modelInfo.version,
                                                   chunkStrategy: config.chunkStrategy.identity,
                                                   dimension: vector.count, vector: vector))
            }
            done += batch.count
            phase = .indexing(done: done, total: chunks.count)
        }

        cachedIndexKey = key
        cachedIndex = store
        return store
    }

    // MARK: D9 —— 失败归因

    func setFailureType(_ type: FailureType?, at index: Int) {
        guard failures.indices.contains(index) else { return }
        failures[index].failureType = type
    }

    func setDiagnosisNote(_ note: String, at index: Int) {
        guard failures.indices.contains(index) else { return }
        failures[index].diagnosisNote = note.isEmpty ? nil : note
    }

    /// D9 唯一的写操作，幂等。
    @discardableResult
    func addToRegressionSet(at index: Int) -> Bool {
        guard failures.indices.contains(index) else { return false }
        return store.addRegression(failures[index])
    }

    func isInRegressionSet(at index: Int) -> Bool {
        guard failures.indices.contains(index) else { return false }
        return store.contains(failures[index])
    }

    func noteTitle(for noteID: String) -> String { corpus.title(noteID: noteID) }

    enum EvalError: Error, CustomStringConvertible {
        case message(String)
        var description: String {
            switch self { case let .message(m): return m }
        }
    }
}
