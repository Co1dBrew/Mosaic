import SwiftUI
import MosaicKit

/// # D2 / D3 —— Retrieval Lab
///
/// 完全用原生控件：`Form` + `Picker` + `List`。唯一的自定义视图是结果卡片，
/// 而它内部只有文本，没有任何自定义绘制（`DEVTOOLS_SWIFTUI_PLAN.md` §1）。
///
/// Compare Modes 是这一页的**第四个 Mode 状态**，不是独立页面
/// （`DECISION_LOG.md` D-UI-DEV-007）：一次检索就能同时拿到三路排名，做成三页
/// 会暗示要 Run 三次。
struct RetrievalLabView: View {

    @State var viewModel: RetrievalLabViewModel
    /// 第四个状态。选中时结果区切换为对比视图，配置与结果都不重跑。
    @State private var comparing = false

    var body: some View {
        Form {
            Section("QUERY") {
                TextField("输入 query", text: $viewModel.query, axis: .vertical)
                    .lineLimit(1...3)
                    .submitLabel(.search)
                    .onSubmit { viewModel.run() }
                Button("Run") { viewModel.run() }
                    .disabled(viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("CONFIGURATION") {
                Picker("Retrieval Mode", selection: $viewModel.mode) {
                    Text("Keyword").tag(RetrievalMode.keyword)
                    Text("Vector").tag(RetrievalMode.vector)
                    Text("Hybrid").tag(RetrievalMode.hybrid)
                }
                LabeledContent("Embedding Provider", value: viewModel.config.embeddingProvider)
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
                LabeledContent("Index", value: viewModel.indexState.description)
                if !viewModel.strategyMatchesIndex {
                    Text("生产索引是用 **\(viewModel.indexedStrategy.identity)** 建的。换成别的策略后 chunkID 全变，vector 路的命中会在这里被丢掉 —— 那不是语义变差，是索引对不上。")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }

            resultsSection
        }
        .navigationTitle("Retrieval Lab")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(comparing ? "Results" : "Compare") { comparing.toggle() }
                    .disabled(viewModel.outcome == nil)
            }
        }
        .task { await viewModel.refreshIndexState() }
    }

    // MARK: 结果区

    @ViewBuilder
    private var resultsSection: some View {
        switch viewModel.phase {
        case .idle:
            Section {
                Text("输入 query 后 Run。结果会给出每条的三路排名证据。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .running:
            Section { HStack { ProgressView(); Text("检索中…").foregroundStyle(.secondary) } }
        case let .error(message):
            Section("ERROR") { Text(message).foregroundStyle(.red) }
        case .empty:
            Section("RESULTS") { Text("没有命中").foregroundStyle(.secondary) }
        case .results:
            if let outcome = viewModel.outcome {
                if comparing { compareSections(outcome) } else { resultRows(outcome) }
                traceSection(outcome)
            }
        }
    }

    @ViewBuilder
    private func resultRows(_ outcome: RetrievalOutcome) -> some View {
        Section("RESULTS · \(outcome.results.count)") {
            ForEach(outcome.results, id: \.chunkID) { result in
                resultCard(result)
            }
        }
    }

    /// D-UI-DEV-002：竖排卡片。393pt 放不下八列横表，所以把三路排名压成一行。
    @ViewBuilder
    private func resultCard(_ result: RetrievalResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("#\(result.fusedRank)").font(.headline)
                Text(viewModel.noteTitle(for: result.ref.noteID))
                    .font(.headline).lineLimit(1)
            }
            Text("\(result.source.rawValue) · \(result.chunkID)")
                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)

            // 对比式高亮：命中片段用主色，上下文压暗（SEARCH_CONTRACT §2.4）。
            highlighted(viewModel.excerpts[result.chunkID])
                .font(.subheadline)

            HStack(spacing: 12) {
                Text(result.rankEvidence)
                    .font(.caption).bold().foregroundStyle(.tint).monospacedDigit()
                if let s = result.similarity {
                    Text(String(format: "similarity %.3f", s))
                        .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 把 excerpt 的高亮区间渲染成 `AttributedString`。
    /// Figma 侧用 per-range fill，这里用 `foregroundColor` —— 两边一一对应
    /// （SEARCH_CONTRACT §2.4 之所以选前景对比而不是背景色块，就是为了这个）。
    private func highlighted(_ excerpt: Excerpt?) -> Text {
        guard let excerpt else { return Text("") }
        let chars = Array(excerpt.text)
        var out = AttributedString()
        var cursor = 0
        for range in excerpt.highlights {
            if range.start > cursor {
                var seg = AttributedString(String(chars[cursor..<min(range.start, chars.count)]))
                seg.foregroundColor = .secondary
                out += seg
            }
            let end = min(range.end, chars.count)
            if range.start < end {
                var seg = AttributedString(String(chars[range.start..<end]))
                seg.foregroundColor = .primary
                out += seg
            }
            cursor = max(cursor, end)
        }
        if cursor < chars.count {
            var seg = AttributedString(String(chars[cursor...]))
            seg.foregroundColor = .secondary
            out += seg
        }
        return Text(out)
    }

    // MARK: D3 —— Compare Modes

    @ViewBuilder
    private func compareSections(_ outcome: RetrievalOutcome) -> some View {
        Section("HYBRID FINAL RANKING") {
            ForEach(outcome.results, id: \.chunkID) { result in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("#\(result.fusedRank)").font(.subheadline).bold()
                        Text(viewModel.noteTitle(for: result.ref.noteID))
                            .font(.subheadline).lineLimit(1)
                        Spacer()
                    }
                    HStack(spacing: 10) {
                        Text(result.rankEvidence).font(.caption).monospacedDigit()
                            .foregroundStyle(.tint)
                        if result.isVectorOnly { Text("vector only").font(.caption).foregroundStyle(.red) }
                        if result.isKeywordOnly { Text("keyword only").font(.caption).foregroundStyle(.red) }
                    }
                }
            }
        }

        // unique hit 才是这一屏的重点：它直接回答「砍掉 vector 会丢什么」。
        Section("UNIQUE HITS") {
            LabeledContent("Keyword only", value: "\(outcome.keywordOnly.count)")
            ForEach(outcome.keywordOnly, id: \.chunkID) { r in
                Text(viewModel.noteTitle(for: r.ref.noteID))
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Vector only", value: "\(outcome.vectorOnly.count)")
            ForEach(outcome.vectorOnly, id: \.chunkID) { r in
                Text(viewModel.noteTitle(for: r.ref.noteID))
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("两路都命中", value: "\(outcome.bothCount)")
        }
    }

    // MARK: Trace 入口

    @ViewBuilder
    private func traceSection(_ outcome: RetrievalOutcome) -> some View {
        Section("TRACE") {
            NavigationLink {
                RetrievalTraceView(trace: outcome.trace)
            } label: {
                LabeledContent("本次检索", value: String(format: "%.1f ms", outcome.trace.totalMs))
                    .monospacedDigit()
            }
        }
    }
}
