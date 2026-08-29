import SwiftUI
import SwiftData
import MosaicKit

// MARK: - 仅内部构建
//
// Developer Tools **整目录**只在 DEBUG 或显式打开 `INTERNAL_BUILD` 的构建里编译。
// 正式 Release 里这些类型根本不存在 —— 不是「入口藏起来」，是**没有这段代码**，
// 所以不可能有第二条路径把它们暴露给普通用户（`design/DEVTOOLS.md` §1.2）。
//
// 内部 TestFlight 需要它时：在 Release 配置的
// `SWIFT_ACTIVE_COMPILATION_CONDITIONS` 里加 `INTERNAL_BUILD`。
#if DEBUG || INTERNAL_BUILD

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
    /// derived 与笔记库的对账结果。`nil` = 这次进入页面还没查过。
    @State private var consistency: DerivedConsistencyReport?

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

            // 孤儿 derived 数据是**静默**的失败：它占掉一个 topK 名额，
            // 搜索页回查笔记失败后把那一行丢掉，用户只看到「少了一条结果」。
            // 所以它必须有一处能被看见的地方。
            Section("一致性") {
                if let report = consistency {
                    LabeledContent("Derived 对账",
                                   value: report.isConsistent ? "一致" : "有孤儿")
                        .foregroundStyle(report.isConsistent ? Color.primary : .red)
                    Text(report.summary)
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !report.isConsistent {
                        Button("清理孤儿数据") {
                            Task {
                                _ = await retrieval.indexing.reconcileOrphans()
                                consistency = await retrieval.derivedConsistency()
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
                Button("重新对账") {
                    Task { consistency = await retrieval.derivedConsistency() }
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
            consistency = await retrieval.derivedConsistency()
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

#endif  // DEBUG || INTERNAL_BUILD
