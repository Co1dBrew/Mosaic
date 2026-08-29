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

/// # D5 —— Eval Center
///
/// 六个数字 + 一个失败入口，**不做图表**（`DEVTOOLS.md` §4.5）：几十条 case 的
/// 评测画折线没有信息量，只有装饰价值。
///
/// 这一页只回答「这套配置多好」。「能不能上线」是 Release Gate 的事（Week 5）。
struct RetrievalEvalView: View {

    @State var viewModel: RetrievalEvalViewModel

    var body: some View {
        Form {
            datasetSection
            configurationSection
            runSection

            if let run = viewModel.run {
                qualitySection(run)
                performanceSection(run)
                breakdownSection(run)
                failuresSection(run)
                compareSection
            }
        }
        .navigationTitle("Eval Center")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Dataset

    @ViewBuilder
    private var datasetSection: some View {
        Section("DATASET") {
            Picker("Dataset", selection: $viewModel.selection) {
                ForEach(EvalDataset.Selection.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            LabeledContent("Cases", value: "\(viewModel.caseCount)").monospacedDigit()

            NavigationLink {
                EvalDatasetView(store: viewModel.store, corpus: corpus, kind: .golden)
            } label: {
                LabeledContent("Golden Set", value: "\(viewModel.store.count(.golden)) cases").monospacedDigit()
            }
            NavigationLink {
                EvalDatasetView(store: viewModel.store, corpus: corpus, kind: .regression)
            } label: {
                LabeledContent("Regression Set", value: "\(viewModel.store.count(.regression)) cases").monospacedDigit()
            }

            // 引用了已删笔记的用例会永远失败，而那不是检索质量问题。不标出来的话，
            // Recall 会被一条坏用例长期压低，且看不出原因。
            let dangling = viewModel.danglingCases
            if !dangling.isEmpty {
                Text("\(dangling.count) 条用例引用了已删除的笔记，它们必然失败 —— 原因不是检索质量。")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if let error = viewModel.store.lastError {
                Text("数据集写盘失败：\(error)").font(.footnote).foregroundStyle(.red)
            }
        }
    }

    // MARK: Configuration

    @ViewBuilder
    private var configurationSection: some View {
        Section("CONFIGURATION") {
            Picker("Retrieval Mode", selection: $viewModel.mode) {
                Text("Keyword").tag(RetrievalMode.keyword)
                Text("Vector").tag(RetrievalMode.vector)
                Text("Hybrid").tag(RetrievalMode.hybrid)
            }
            Picker("Chunk Strategy", selection: $viewModel.chunkStrategy) {
                Text("Block").tag(ChunkStrategy.block)
                Text("Fixed 240/40").tag(ChunkStrategy.fixed(maxChars: 240, overlap: 40))
                Text("Sentence 240").tag(ChunkStrategy.sentence(maxChars: 240))
            }
            Picker("Top K", selection: $viewModel.topK) {
                ForEach([5, 10, 20, 50], id: \.self) { Text("\($0)").tag($0) }
            }
            Picker("Fusion", selection: $viewModel.fusion) {
                Text("RRF k=60").tag(FusionMethod.rrf(k: 60))
                Text("RRF k=10").tag(FusionMethod.rrf(k: 10))
                Text("Weighted 1/1").tag(FusionMethod.weighted(keyword: 1, vector: 1))
            }
            LabeledContent("Embedding", value: viewModel.config.embeddingVersion)
                .foregroundStyle(viewModel.providerAvailable ? Color.primary : Color.red)
            if !viewModel.providerAvailable {
                Text("本机没有可用的本地句向量模型。**不退回 mock** —— 伪向量会让 Recall 看起来正常但毫无含义。Keyword 模式仍可评测。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Run

    @ViewBuilder
    private var runSection: some View {
        Section {
            switch viewModel.phase {
            case .idle, .done, .failed:
                Button("Run Evaluation") { viewModel.run() }
                    .disabled(viewModel.caseCount == 0)
            case .preparing:
                HStack { ProgressView(); Text("准备中…").foregroundStyle(.secondary) }
                Button("Cancel", role: .destructive) { viewModel.cancel() }
            case let .indexing(done, total):
                VStack(alignment: .leading, spacing: 6) {
                    // 建索引与跑评测分开显示：建索引不计入延迟指标，混在一起会让人
                    // 以为 P95 包含了嵌入耗时。
                    Text("建立评测索引 \(done) / \(total)").font(.footnote).monospacedDigit()
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                }
                Button("Cancel", role: .destructive) { viewModel.cancel() }
            case let .running(done, total):
                VStack(alignment: .leading, spacing: 6) {
                    Text("评测中 \(done) / \(total)").font(.footnote).monospacedDigit()
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                }
                Button("Cancel", role: .destructive) { viewModel.cancel() }
            }

            if case let .failed(message) = viewModel.phase {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    // MARK: 结果

    @ViewBuilder
    private func qualitySection(_ run: EvalRun) -> some View {
        Section("QUALITY") {
            LabeledContent("Gate Scope", value: "In-scope · \(run.inScopeMetrics.caseCount) cases")
                .font(.footnote)
            metric("Recall@1", run.inScopeMetrics.recallAt1)
            metric("Recall@3", run.inScopeMetrics.recallAt3)
            metric("Recall@5", run.inScopeMetrics.recallAt5)
            metric("MRR", run.inScopeMetrics.mrr)
            if run.crossLanguageMetrics.caseCount > 0 {
                metric("Cross-language · Recall@5", run.crossLanguageMetrics.recallAt5)
                metric("Cross-language · MRR", run.crossLanguageMetrics.mrr)
                Text("Cross-language 是当前架构边界，只作诊断，不进入 Gate。")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if run.metrics.noResultCaseCount > 0 {
                metric("No-result Accuracy", run.metrics.noResultAccuracy)
                metric("False-positive Rate", run.metrics.falsePositiveRate)
                Text("负例只有返回空列表才算通过；这两项暂不进入 Release Gate。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func performanceSection(_ run: EvalRun) -> some View {
        Section("PERFORMANCE") {
            LabeledContent("P50", value: String(format: "%.0f ms", run.inScopeMetrics.p50Ms)).monospacedDigit()
            LabeledContent("P95", value: String(format: "%.0f ms", run.inScopeMetrics.p95Ms)).monospacedDigit()
            Text("只统计检索本身，不含建索引、不含 UI。与 PRD 的 SLO 同一口径。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func breakdownSection(_ run: EvalRun) -> some View {
        Section("RUN") {
            LabeledContent("Config", value: run.configVersion)
                .font(.footnote)
            LabeledContent("Cases", value: "\(run.metrics.caseCount)").monospacedDigit()
            LabeledContent("In-scope / Cross-language",
                           value: "\(run.inScopeMetrics.caseCount) / \(run.crossLanguageMetrics.caseCount)")
                .monospacedDigit()
            if run.metrics.noResultCaseCount > 0 {
                LabeledContent("Relevant / No-result",
                               value: "\(run.metrics.relevantCaseCount) / \(run.metrics.noResultCaseCount)")
                    .monospacedDigit()
            }
            if run.goldenMetrics.caseCount > 0 {
                metric("Golden · Recall@5", run.goldenMetrics.recallAt5)
            }
            if run.regressionMetrics.caseCount > 0 {
                metric("Regression Pass Rate", run.regressionPassRate)
                Text("与 Recall@5 同口径 —— 避免出现两套「通过」的定义。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func failuresSection(_ run: EvalRun) -> some View {
        Section("FAILURES") {
            if viewModel.failures.isEmpty {
                Text("没有失败用例。").foregroundStyle(.secondary)
            } else {
                NavigationLink {
                    FailureListView(viewModel: viewModel)
                } label: {
                    LabeledContent("Failed Cases", value: "\(viewModel.failures.count)").monospacedDigit()
                }
                let triaged = viewModel.failures.filter(\.isTriaged).count
                Text("已归因 \(triaged) / \(viewModel.failures.count)。未归因的失败没有统计价值。")
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var compareSection: some View {
        Section {
            NavigationLink("Compare With Baseline") {
                EvalComparisonView(viewModel: viewModel)
            }
        } footer: {
            Text("Eval 只负责讲清 trade-off，不下 PASS / FAIL —— 判定是 Release Gate 的事。")
        }
    }

    private func metric(_ label: String, _ value: Double) -> some View {
        LabeledContent(label, value: String(format: "%.3f", value)).monospacedDigit()
    }

    private var corpus: NoteCorpus { viewModel.corpus }
}

#endif  // DEBUG || INTERNAL_BUILD
