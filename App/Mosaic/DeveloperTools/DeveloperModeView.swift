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
                    Text(retrieval.route.explanation)
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    LabeledContent("Embedding Provider", value: "不可用")
                        .foregroundStyle(.red)
                    Text(retrieval.route.explanation)
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
                if let desired = retrieval.desiredRoute {
                    // 路线该变了，但**不自动变** —— 换向量空间要清空索引 + 全库重嵌，
                    // 可能还是付费调用。给一个显式入口，别在用户打字时替他决定。
                    Text("路线需要变更：\(desired.explanation)")
                        .font(.footnote).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(retrieval.hasPendingRouteChange ? "Apply Route & Rescan" : "Rescan Now") {
                    Task {
                        await retrieval.applyDesiredRoute()
                        await retrieval.indexing.indexAll()
                    }
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
    /// 当前路线选中的 provider。`nil` = 语义不可用。**不退回 mock**。
    private(set) var provider: (any EmbeddingProvider)?
    /// 为什么选了这一路。Developer Mode 原样展示。
    private(set) var route: EmbeddingRoute
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
    private let settings: SettingsStore?

    init(provider: (any EmbeddingProvider)?,
         vectors: InMemoryVectorStore,
         recorder: RetrievalTraceRecorder,
         derived: DerivedDataStore,
         indexing: IndexingService,
         release: ReleaseStore? = nil,
         evalDatasets: EvalDatasetStore? = nil,
         settings: SettingsStore? = nil,
         route: EmbeddingRoute = .unavailable("尚未选择 embedding 路线")) {
        self.provider = provider
        self.route = route
        self.vectors = vectors
        self.recorder = recorder
        self.derived = derived
        self.indexing = indexing
        self.release = release ?? ReleaseStore()
        self.evalDatasets = evalDatasets ?? EvalDatasetStore()
        self.settings = settings
    }

    var indexedCount: Int { indexing.indexedChunks }

    /// 库里有没有中文 —— **缓存值**。全库扫描实测 200 篇约 26ms 且在 main actor 上，
    /// 放进编辑路径会随库线性变成打字卡顿。只在低频时机（启动 / 手动 Rescan /
    /// 设置变更）重算，编辑时只看被改的那一篇（见 `noteDidChange`）。
    private(set) var corpusHasHan = false

    /// 按当前语料 + 设置**应该**走的路线。与 `route`（当前生效的）不同时，
    /// 说明需要一次重建索引才能切过去。
    ///
    /// **不自动切。** 换向量空间 = 清空索引 + 全库重嵌，而且可能是付费云端调用；
    /// 在用户打字打到一半时替他做这个决定是不合适的。UI 据此给一个显式入口。
    private(set) var desiredRoute: EmbeddingRoute?

    /// 有待用户确认的路线变更。
    var hasPendingRouteChange: Bool { desiredRoute != nil }

    /// 启动：先按库里有没有中文选定 provider，再灌回落盘向量、补齐缺的。
    func startIndexing() async {
        // 启动不是热路径，这里做一次全库扫描是合理的。
        await resolveProvider(rescanCorpus: true, rebuildIfChanged: false)
        await indexing.start()
    }

    /// 重选路线并应用。
    ///
    /// - Parameter rescanCorpus: 是否重扫全库判定「有没有中文」。**只在低频时机传 true。**
    /// - Parameter rebuildIfChanged: 换了向量空间是否立刻重建索引。
    func resolveProvider(rescanCorpus: Bool = true, rebuildIfChanged: Bool = true) async {
        if rescanCorpus {
            corpusHasHan = ProductionEmbedding.corpusContainsHan(cards: indexing.fetchCards(),
                                                                 derived: derived)
        }
        let decision = currentDecision()
        route = decision.route
        provider = decision.provider
        desiredRoute = nil
        let reason: String?
        if case .unavailable(let message) = decision.route { reason = message } else { reason = nil }
        if rebuildIfChanged {
            await indexing.applyProvider(decision.provider, unavailableReason: reason)
        } else {
            indexing.adoptProvider(decision.provider, unavailableReason: reason)
        }
    }

    private func currentDecision() -> ProductionEmbedding.Decision {
        ProductionEmbedding.decide(
            corpusContainsHan: corpusHasHan,
            cloudConfigured: settings?.isCloudEmbeddingConfigured ?? false,
            cloudConsentGranted: settings?.hasAcceptedCloudEmbeddingNotice ?? false,
            makeCloud: { settings?.makeCloudEmbeddingProvider() ?? .failure(.unavailable("未配置")) }
        )
    }

    /// 一次编辑之后。**这是热路径，必须便宜。**
    ///
    /// 索引照常走 `IndexingService` 自己的合并 + 600ms 防抖；
    /// 路线这边只做一次**单篇**汉字判定，而且**只升不降**：
    ///
    /// - 这一篇出现了汉字而缓存还是 false → 缓存升为 true，标记「路线需要变更」，
    ///   **但不重建**（等用户确认）。
    /// - 这一篇没有汉字 → 什么都不做。判断「是不是最后一篇中文笔记被清空了」需要
    ///   全库扫描，而降级不紧急（英文库用着云端只是浪费，不是错），
    ///   留给下次启动或手动 Rescan。这样也避免了打字时路线来回翻。
    func noteDidChange(_ noteID: String) {
        indexing.noteDidChange(noteID)
        guard !corpusHasHan else { return }
        guard let card = indexing.card(withID: noteID),
              ProductionEmbedding.noteContainsHan(card, derived: derived) else { return }
        corpusHasHan = true
        refreshDesiredRoute()
    }

    func noteWasDeleted(_ noteID: String) async {
        await indexing.noteWasDeleted(noteID)
        // 删笔记同样不重扫全库：这里不会**新增**中文，只可能减少，而降级不紧急。
        refreshDesiredRoute()
    }

    /// 设置变了（填了 Key、给了同意）→ 重新看一眼应该走哪条，但不擅自重建。
    func refreshDesiredRoute() {
        let decision = currentDecision()
        desiredRoute = decision.route == route ? nil : decision.route
    }

    /// 用户确认切换路线（Developer Mode 的 Rescan / 搜索状态条的入口）。
    func applyDesiredRoute() async {
        await resolveProvider(rescanCorpus: true, rebuildIfChanged: true)
    }

    /// 同意云端上传。**唯一把同意写进设置的地方**，写完立刻切换路线。
    func grantCloudEmbeddingConsent() async {
        settings?.hasAcceptedCloudEmbeddingNotice = true
        await applyDesiredRoute()
    }
}
