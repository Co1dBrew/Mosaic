import SwiftUI
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

/// # D6 —— Eval Center · Compare
///
/// 回答「新配置比 baseline 好还是差、代价是什么」。
///
/// **质量与延迟必须在同一张表里**（`DECISION_LOG.md` D-UI-DEV-003）：分开放会让人
/// 只看 Recall 就下结论。Delta 用颜色区分方向，但**不给 PASS / FAIL** ——
/// Eval 的任务是理解 trade-off，判定是 Release Gate 的事。
struct EvalComparisonView: View {

    @State var viewModel: RetrievalEvalViewModel

    var body: some View {
        List {
            Section("BASELINE CONFIG") {
                Picker("Retrieval Mode", selection: $viewModel.baselineMode) {
                    Text("Keyword").tag(RetrievalMode.keyword)
                    Text("Vector").tag(RetrievalMode.vector)
                    Text("Hybrid").tag(RetrievalMode.hybrid)
                }
                Picker("Chunk Strategy", selection: $viewModel.baselineChunkStrategy) {
                    Text("Block").tag(ChunkStrategy.block)
                    Text("Fixed 240/40").tag(ChunkStrategy.fixed(maxChars: 240, overlap: 40))
                    Text("Sentence 240").tag(ChunkStrategy.sentence(maxChars: 240))
                }
                Picker("Top K", selection: $viewModel.baselineTopK) {
                    ForEach([5, 10, 20, 50], id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Fusion", selection: $viewModel.baselineFusion) {
                    Text("RRF k=60").tag(FusionMethod.rrf(k: 60))
                    Text("RRF k=10").tag(FusionMethod.rrf(k: 10))
                    Text("Weighted 1/1").tag(FusionMethod.weighted(keyword: 1, vector: 1))
                }
            }

            Section {
                if viewModel.isBusy {
                    HStack { ProgressView(); Text(progressText).foregroundStyle(.secondary).monospacedDigit() }
                    Button("Cancel", role: .destructive) { viewModel.cancel() }
                } else {
                    Button("Run Baseline") { viewModel.run(baseline: true) }
                        .disabled(viewModel.run == nil || viewModel.caseCount == 0)
                }
                if viewModel.run == nil {
                    Text("先在 Eval Center 跑一次当前配置，才有东西可比。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    // baseline 跑的是 current 当时那一批用例，不是「现在的数据集」。
                    Text("Baseline 跑 current 当时的那 \(viewModel.evaluatedCases.count) 条用例 —— 用例集变了就不是同一把尺子。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if case let .failed(message) = viewModel.phase {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }

            if !viewModel.deltas.isEmpty {
                comparisonTable
                tradeoffSection
                failuresLink
            } else if viewModel.baselineRun != nil && !viewModel.isComparable {
                Section {
                    Text("两次跑批的用例数不同，delta 里混着「用例集变了」，不可比。请重跑 current。")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 四列表 —— 唯一需要对齐处理的地方（`DEVTOOLS_SWIFTUI_PLAN.md` §5）

    @ViewBuilder
    private var comparisonTable: some View {
        Section {
            headerRow
            ForEach(viewModel.deltas) { delta in
                HStack(spacing: 0) {
                    Text(delta.label).frame(width: 105, alignment: .leading)
                    Text(delta.formatted(delta.current)).frame(width: 74, alignment: .trailing)
                    Text(delta.formatted(delta.baseline)).frame(width: 74, alignment: .trailing)
                    Text(delta.direction == .unchanged ? "—" : delta.deltaText)
                        .frame(width: 74, alignment: .trailing)
                        .foregroundStyle(color(for: delta.direction))
                        .bold(delta.direction != .unchanged)
                }
                .font(.subheadline)
                .monospacedDigit()
            }
        } header: {
            Text("""
                 CURRENT \(viewModel.run?.configVersion ?? "")
                 BASELINE \(viewModel.baselineRun?.configVersion ?? "")
                 \(viewModel.run?.metrics.caseCount ?? 0) cases
                 """)
                .font(.caption2)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Metric").frame(width: 105, alignment: .leading)
            Text("Current").frame(width: 74, alignment: .trailing)
            Text("Baseline").frame(width: 74, alignment: .trailing)
            Text("Delta").frame(width: 74, alignment: .trailing)
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func color(for direction: MetricDelta.Direction) -> Color {
        switch direction {
        case .better: return .green
        case .worse: return .red
        case .unchanged: return .secondary
        }
    }

    @ViewBuilder
    private var tradeoffSection: some View {
        Section("TRADE-OFF") {
            if let summary = viewModel.tradeoffSummary {
                Text(summary).font(.subheadline)
            }
            Text("这里不给 PASS / FAIL。判定是 Release Gate 的事（Week 5）。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var failuresLink: some View {
        if !viewModel.failures.isEmpty {
            Section {
                NavigationLink {
                    FailureListView(viewModel: viewModel)
                } label: {
                    LabeledContent("Failed Cases", value: "\(viewModel.failures.count)").monospacedDigit()
                }
            } footer: {
                Text("失败用例来自 current 这一次跑批。")
            }
        }
    }

    private var progressText: String {
        switch viewModel.phase {
        case let .indexing(done, total): return "建立评测索引 \(done) / \(total)"
        case let .running(done, total):  return "评测中 \(done) / \(total)"
        case .preparing: return "准备中…"
        default: return ""
        }
    }
}

#endif  // DEBUG || INTERNAL_BUILD
