import SwiftUI
import SwiftData
import MosaicKit

/// # D1 —— Developer Mode
///
/// **纯入口列表。不做 Dashboard，不做 KPI overview**
/// （`DECISION_LOG.md` D-UI-DEV-010）。它的职责是分发，不是汇报 ——
/// 用的人知道自己要去哪。
///
/// 整个 Developer Tools 目录只在内部构建里编译（见文件末尾的构建约定说明）。
struct DeveloperModeView: View {
    @Environment(\.modelContext) private var noteContext
    @Environment(RetrievalEnvironment.self) private var retrieval

    /// Eval Center 与 Release Gate 共用**同一个** ViewModel。
    /// 各自 `NavigationLink` 里现场 new 一个的话，Gate 上看到的失败会和 Eval 里
    /// 刚标注过的那批对不上 —— 归因是会话内的工作状态，不是从磁盘读回来的。
    @State private var eval: RetrievalEvalViewModel?

    var body: some View {
        List {
            Section("检索") {
                NavigationLink("Retrieval Lab") {
                    RetrievalLabView(viewModel: RetrievalLabViewModel(
                        // provider 为 nil 时**不塞 mock**：Lab 会如实显示语义路不可用，
                        // 而不是用伪向量排出一份看起来正常的顺序。
                        provider: retrieval.provider,
                        vectors: retrieval.vectors,
                        recorder: retrieval.recorder,
                        derived: retrieval.derived,
                        noteContext: noteContext,
                        indexedStrategy: retrieval.indexing.config.chunkStrategy
                    ))
                }
                if let eval {
                    NavigationLink("Retrieval Eval") { RetrievalEvalView(viewModel: eval) }
                }
                NavigationLink("Retrieval Trace") {
                    RecentTracesView(recorder: retrieval.recorder)
                }
            }

            Section("发布") {
                NavigationLink("Release Gate") {
                    ReleaseGateView(viewModel: ReleaseGateViewModel(store: retrieval.release,
                                                                    indexing: retrieval.indexing),
                                    eval: eval)
                }
                NavigationLink("Retrieval Config") {
                    RetrievalConfigView(store: retrieval.release)
                }
                LabeledContent("Production Config", value: retrieval.release.productionConfig.version)
                    .font(.footnote)
                if let candidate = retrieval.release.registry.candidate {
                    LabeledContent("Candidate", value: candidate.config.version)
                        .font(.footnote).foregroundStyle(.tint)
                }
            }

            Section("配置") {
                if let info = retrieval.provider?.modelInfo {
                    LabeledContent("Embedding Provider", value: info.identifier)
                    LabeledContent("Embedding Version", value: info.version)
                    LabeledContent("Dimension", value: "\(info.dimension)").monospacedDigit()
                } else {
                    LabeledContent("Embedding Provider", value: "不可用")
                        .foregroundStyle(.red)
                    Text("本机没有可用的本地句向量模型，语义检索不可用；关键词搜索不受影响。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("索引") {
                LabeledContent("Index State", value: retrieval.indexing.state.description)
                LabeledContent("Indexed Chunks", value: "\(retrieval.indexing.indexedChunks)")
                    .monospacedDigit()
                if retrieval.indexing.pendingChunks > 0 {
                    LabeledContent("Pending", value: "\(retrieval.indexing.pendingChunks)")
                        .monospacedDigit().foregroundStyle(.orange)
                }
                LabeledContent("Chunk Strategy", value: retrieval.indexing.config.chunkStrategy.identity)
                    .font(.footnote)
                Button("Rescan Now") {
                    Task { await retrieval.indexing.indexAll() }
                }
                if let error = retrieval.indexing.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red).lineLimit(3)
                }
            }

            Section {
                Text("这些工具只面向开发者与 AI TPM。普通用户不会看到本页，也不会在产品界面里见到 embedding / 向量 / RRF 等词。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("开发者模式")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if eval == nil {
                eval = RetrievalEvalViewModel(
                    store: retrieval.evalDatasets,
                    provider: retrieval.provider,
                    corpus: NoteCorpus(noteContext: noteContext, derived: retrieval.derived),
                    release: retrieval.release)
            }
            await retrieval.indexing.refreshState()
        }
    }
}

/// 最近若干次检索。Trace 记录是内存环形缓冲，App 退出即丢
/// （`DECISION_LOG.md` D-UI-DEV-012）。
struct RecentTracesView: View {
    let recorder: RetrievalTraceRecorder
    @State private var traces: [RetrievalTrace] = []

    var body: some View {
        List {
            if traces.isEmpty {
                Text("还没有检索记录。去 Retrieval Lab 跑一次。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(traces) { trace in
                NavigationLink {
                    RetrievalTraceView(trace: trace)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trace.query).lineLimit(1)
                        HStack(spacing: 8) {
                            Text(String(format: "%.1f ms", trace.totalMs)).monospacedDigit()
                            Text("· \(trace.resultCount) 条")
                            if trace.isStale { Text("· STALE").foregroundStyle(.red) }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Trace")
        .navigationBarTitleDisplayMode(.inline)
        .task { traces = await recorder.recent() }
    }
}

/// 检索栈的持有者，注入给 Developer Tools。
///
/// 只有 `RetrievalTraceRecorder` 是**无条件**存在的（SLO 需要在真实用户路径上
/// 采集，`DECISION_LOG.md` D-UI-DEV-012）；其余在 Developer Mode 关闭时不会被触达。
@Observable
@MainActor
final class RetrievalEnvironment {
    /// `nil` = 本机没有可用的本地模型。**不退回 mock**：退回会让 Recall 看起来
    /// 正常但毫无产品含义。
    let provider: (any EmbeddingProvider)?
    let vectors: InMemoryVectorStore
    let recorder: RetrievalTraceRecorder
    let derived: DerivedDataStore
    /// Golden / Regression Set。**不放 derived store** —— 那里的契约是「可以随时清空」，
    /// 而人工标注的用例删了就得重标（见 `EvalDatasetStore`）。
    let evalDatasets: EvalDatasetStore
    /// TD-8：把索引真正建起来的那条接线。**不是 Developer Tools 专属** ——
    /// 生产搜索（Week 5）要用的是同一个实例。
    let indexing: IndexingService
    /// 配置注册表 + 上线阈值 + 最近一次跑批（backlog 5.1–5.4）。
    /// 生产配置从它来 —— 否则 Promote 就只是改了一行 JSON。
    let release: ReleaseStore

    init(provider: (any EmbeddingProvider)?,
         vectors: InMemoryVectorStore,
         recorder: RetrievalTraceRecorder,
         derived: DerivedDataStore,
         indexing: IndexingService,
         release: ReleaseStore? = nil,
         evalDatasets: EvalDatasetStore? = nil) {
        self.provider = provider
        self.vectors = vectors
        self.recorder = recorder
        self.derived = derived
        self.indexing = indexing
        self.release = release ?? ReleaseStore()
        self.evalDatasets = evalDatasets ?? EvalDatasetStore()
    }

    var indexedCount: Int { indexing.indexedChunks }

    /// 启动：先把落盘的向量灌回内存，再补齐缺的。
    func startIndexing() async {
        await indexing.start()
    }
}
