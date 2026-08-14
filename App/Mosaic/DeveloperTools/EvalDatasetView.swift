import SwiftUI
import MosaicKit

/// # Dataset 管理（`DEVTOOLS.md` §6.2）
///
/// 一个 `List` + 左滑删除，Golden 侧多一个「加一条」。**不建 Dataset Management
/// Platform** —— 不做版本化 / 分支 / 导入导出 / 协作 / 标签。
struct EvalDatasetView: View {

    enum Kind { case golden, regression }

    @State var store: EvalDatasetStore
    let corpus: NoteCorpus
    let kind: Kind

    @State private var adding = false

    private var cases: [EvalCase] {
        kind == .golden ? store.dataset.golden : store.dataset.regression.cases
    }

    var body: some View {
        List {
            if cases.isEmpty {
                Section {
                    Text(kind == .golden
                         ? "Golden Set 为空。用例要标在**这台设备上的真实笔记**上 —— 笔记 id 是本机的，没有可以预置的种子数据。"
                         : "回归集为空。它由 Failure Inspection 的 `Add to Regression Set` 生长，不手工维护。")
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }

            ForEach(cases) { c in
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.query).font(.subheadline)
                    Text(c.expectedNoteIDs.map { corpus.title(noteID: $0) }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 8) {
                        if let type = c.sourceFailureType {
                            Text(type.label).font(.caption2).foregroundStyle(.tint)
                        }
                        if let note = c.note, !note.isEmpty {
                            Text(note).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                }
                .swipeActions {
                    Button("删除", role: .destructive) {
                        if kind == .golden { store.removeGolden(id: c.id) } else { store.removeRegression(id: c.id) }
                    }
                }
            }
        }
        .navigationTitle(kind == .golden ? "Golden Set" : "Regression Set")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if kind == .golden {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack { GoldenCaseEditor(store: store, corpus: corpus) }
        }
    }
}

/// 标一条 Golden 用例：一句 query + 它**应该**召回哪几篇笔记。
///
/// 期望笔记必须从真实笔记里挑，而不是手输 id：手输 id 会产出永远失败的用例，
/// 而那种失败看起来和检索质量问题一模一样。
struct GoldenCaseEditor: View {

    @State var store: EvalDatasetStore
    let corpus: NoteCorpus
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var note = ""
    @State private var selected: Set<String> = []
    @State private var duplicate = false

    var body: some View {
        Form {
            Section("QUERY") {
                TextField("这条 query 应该找到什么？", text: $query, axis: .vertical).lineLimit(1...3)
                TextField("备注（为什么值得测）", text: $note)
            }

            Section("EXPECTED NOTES") {
                let notes = corpus.notes()
                if notes.isEmpty {
                    Text("这台设备上还没有笔记。").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(notes) { n in
                    Button {
                        if selected.contains(n.id) { selected.remove(n.id) } else { selected.insert(n.id) }
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.title).lineLimit(1).foregroundStyle(.primary)
                                // 没有标题的笔记全叫「未命名笔记」，只有正文能区分它们。
                                Text(n.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            if selected.contains(n.id) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }

            Section {
                if duplicate {
                    Text("这条用例已经在集合里了 —— 重复加入会让分母虚高。")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Text("多个期望笔记时，**全部**落在 Top K 才算命中。宽松口径会让「找到一半」和「全找到」一样好。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("新增 Golden 用例")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let added = store.addGolden(query: query,
                                                expectedNoteIDs: Array(selected).sorted(),
                                                note: note.isEmpty ? nil : note)
                    if added { dismiss() } else { duplicate = true }
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selected.isEmpty)
            }
        }
    }
}
