import SwiftUI
import MosaicKit

/// 失败用例列表。D5 与 D6 都从这里进 D9，**是同一个 View**，只是数据源不同
/// （`DEVTOOLS.md` §5.4）。
struct FailureListView: View {

    @State var viewModel: RetrievalEvalViewModel
    /// D8 的 `Open Failures` 只看 regression 失败的那几条（`DEVTOOLS.md` §5.4）——
    /// 发布阶段关心的是「哪一条回归挂了」，不是整批评测的全部失败。
    /// 下标仍然是 `viewModel.failures` 里的真实下标：过滤发生在 enumerate **之后**，
    /// 否则 D9 会打开另一条用例。
    var restrictToRegression: Bool = false

    private var entries: [(offset: Int, element: EvalFailure)] {
        Array(viewModel.failures.enumerated())
            .filter { !restrictToRegression || $0.element.evalCase.source == .regression }
            .map { (offset: $0.offset, element: $0.element) }
    }

    var body: some View {
        List {
            if entries.isEmpty {
                Text(restrictToRegression
                     ? "回归集里没有失败用例。"
                     : "这一批跑批没有失败用例。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(entries, id: \.element.evalCase.id) { index, failure in
                NavigationLink {
                    FailureInspectionView(viewModel: viewModel, index: index)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(failure.evalCase.query).font(.subheadline).lineLimit(2)
                        HStack(spacing: 8) {
                            // 未归因的失败没有统计价值 —— 列表要一眼看出还剩几条没标。
                            Text(failure.failureType?.label ?? "未归因")
                                .font(.caption)
                                .foregroundStyle(failure.isTriaged ? Color.accentColor : .orange)
                            Text(rankSummary(failure)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("Failed Cases")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rankSummary(_ f: EvalFailure) -> String {
        let k = f.keywordRank.map { "K #\($0)" } ?? "K —"
        let v = f.vectorRank.map { "V #\($0)" } ?? "V —"
        let h = f.hybridRank.map { "→ #\($0)" } ?? "→ not found"
        return "\(k) · \(v) \(h)"
    }
}

/// # D9 —— Failure Inspection
///
/// 一条失败用例的全部证据 + 人工归因 + 唯一的写操作 `Add to Regression Set`
/// （`DEVTOOLS.md` §5）。
///
/// 归因固定 7 类、不可自由输入：Failure Type 是拿来统计的（「这一轮 60% 的失败是
/// chunking」），自由文本没有统计价值。
struct FailureInspectionView: View {

    @State var viewModel: RetrievalEvalViewModel
    let index: Int

    @State private var diagnosisNote: String = ""

    private var failure: EvalFailure? {
        viewModel.failures.indices.contains(index) ? viewModel.failures[index] : nil
    }

    var body: some View {
        List {
            if let failure {
                Section("QUERY") {
                    Text(failure.evalCase.query)
                    if let note = failure.evalCase.note, !note.isEmpty {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                expectedSection(failure)
                returnedSection(failure)
                perModeSection(failure)
                diagnosisSection(failure)
                actionSection(failure)
            } else {
                Text("这条失败用例已经不在当前跑批里了。").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Failure")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { diagnosisNote = failure?.diagnosisNote ?? "" }
    }

    // MARK: Expected / Returned

    @ViewBuilder
    private func expectedSection(_ failure: EvalFailure) -> some View {
        Section("EXPECTED") {
            ForEach(failure.evalCase.expectedNoteIDs, id: \.self) { noteID in
                let returned = failure.returnedNoteIDs.contains(noteID)
                LabeledContent {
                    Text(returned ? "returned" : "not returned")
                        .font(.caption)
                        .foregroundStyle(returned ? Color.secondary : Color.red)
                } label: {
                    Text(viewModel.noteTitle(for: noteID)).lineLimit(1)
                }
            }
            Text("多个期望笔记时，全部落在 Top 5 才算通过 —— 与 Recall@5 同口径。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func returnedSection(_ failure: EvalFailure) -> some View {
        Section("RETURNED · TOP \(failure.returnedNoteIDs.count)") {
            if failure.returnedNoteIDs.isEmpty {
                // 候选为零和「排序不对」是两类问题，不能混为一谈。
                Text("一条都没返回 —— 问题在检索层，不在排序层。")
                    .font(.footnote).foregroundStyle(.orange)
            }
            ForEach(Array(failure.returnedNoteIDs.enumerated()), id: \.offset) { i, noteID in
                LabeledContent {
                    Text(failure.evalCase.expectedNoteIDs.contains(noteID) ? "expected" : "")
                        .font(.caption).foregroundStyle(.tint)
                } label: {
                    HStack(spacing: 8) {
                        Text("#\(i + 1)").monospacedDigit().foregroundStyle(.secondary)
                        Text(viewModel.noteTitle(for: noteID)).lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func perModeSection(_ failure: EvalFailure) -> some View {
        Section("PER-MODE RANK") {
            LabeledContent("Keyword", value: failure.keywordRank.map { "#\($0)" } ?? "not found")
                .monospacedDigit()
            LabeledContent("Vector", value: failure.vectorRank.map { "#\($0)" } ?? "not found")
                .monospacedDigit()
            LabeledContent("Hybrid", value: failure.hybridRank.map { "#\($0)" } ?? "not found")
                .monospacedDigit()
            Text("名次是第一条期望笔记在各路的位置。单路很靠前而 Hybrid 掉出 Top K，指向 fusion；两路都 not found，指向语料或索引。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: 归因

    @ViewBuilder
    private func diagnosisSection(_ failure: EvalFailure) -> some View {
        Section("DIAGNOSIS") {
            Picker("Failure Type", selection: Binding(
                get: { failure.failureType },
                set: { viewModel.setFailureType($0, at: index) }
            )) {
                Text("未归因").tag(FailureType?.none)
                ForEach(FailureType.allCases, id: \.self) { Text($0.label).tag(FailureType?.some($0)) }
            }
            if let type = failure.failureType {
                Text(type.evidenceHint).font(.footnote).foregroundStyle(.secondary)
            }
            TextField("说明（other 必填）", text: $diagnosisNote, axis: .vertical)
                .lineLimit(1...3)
                .onChange(of: diagnosisNote) { _, new in viewModel.setDiagnosisNote(new, at: index) }
        }
    }

    @ViewBuilder
    private func actionSection(_ failure: EvalFailure) -> some View {
        let alreadyIn = viewModel.isInRegressionSet(at: index)
        Section {
            Button(alreadyIn ? "In Regression Set" : "Add to Regression Set") {
                viewModel.addToRegressionSet(at: index)
            }
            .disabled(alreadyIn || !failure.isTriaged
                      || (failure.failureType == .other && diagnosisNote.isEmpty))
        } footer: {
            Text(alreadyIn
                 ? "已在回归集中。重复加入会让 Pass Rate 的分母虚高，所以按钮禁用。"
                 : "先归因再加入 —— 没有归因的回归用例只能告诉你「又挂了」，不能告诉你挂在哪一层。")
        }
    }
}
