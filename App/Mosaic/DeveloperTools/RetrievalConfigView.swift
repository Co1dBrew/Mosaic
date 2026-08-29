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

/// # Retrieval Config（`DEVTOOLS.md` §4.6 · backlog 5.1）
///
/// 设计侧刻意没有给它线框，理由是「它就是 D2 那六个 Picker 的持久化版本，
/// 没有新的布局决策」。所以这里就是一个 `Form`。
///
/// **唯一的产品规定：不做自由编辑生产配置。**
/// 界面上只有 `Duplicate as new version` 和 `Set as candidate`；
/// 换掉生产配置的路径只有一条 —— Release Gate 的 Promote。
struct RetrievalConfigView: View {

    @State var store: ReleaseStore

    /// 正在编辑的那份派生配置。`nil` = 还没派生。
    @State private var draftID: String?
    @State private var draft: RetrievalConfig = .production

    var body: some View {
        List {
            productionSection
            if let draftID {
                draftSection(id: draftID)
            } else {
                Section {
                    Button("Duplicate as new version") { duplicateFromProduction() }
                } footer: {
                    Text("从生产配置派生一份新版本。派生出来的是 draft —— 派生本身不表达「我要上这个」。")
                        .font(.footnote)
                }
            }
            versionsSection
            thresholdsSection
            if let error = store.lastError {
                Section { Text(error).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Retrieval Config")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 生产配置 —— 只读

    @ViewBuilder
    private var productionSection: some View {
        Section {
            let record = store.registry.production
            LabeledContent("Version", value: record.config.version)
            LabeledContent("Mode", value: record.config.mode.rawValue)
            LabeledContent("Chunk Strategy", value: record.config.chunkStrategy.identity).font(.footnote)
            LabeledContent("Top K", value: "\(record.config.topK)").monospacedDigit()
            LabeledContent("Fusion", value: record.config.fusion.description).font(.footnote)
            LabeledContent("Created", value: Format.relative(record.createdAt)).font(.footnote)
            if let promotedAt = record.promotedAt {
                LabeledContent("Promoted", value: Format.relative(promotedAt)).font(.footnote)
            } else {
                LabeledContent("Promoted", value: "初始配置").font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("PRODUCTION")
        } footer: {
            Text("只读。生产配置只能通过 Release Gate 的 Promote 更换 —— 这不是界面约定，是注册表里没有别的入口。")
                .font(.footnote)
        }
    }

    // MARK: 派生出来的候选

    @ViewBuilder
    private func draftSection(id: String) -> some View {
        Section {
            Picker("Mode", selection: $draft.mode) {
                ForEach(RetrievalMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Chunk Strategy", selection: Binding(
                get: { ChunkStrategyOption(draft.chunkStrategy) },
                set: { draft.chunkStrategy = $0.strategy }
            )) {
                ForEach(ChunkStrategyOption.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Stepper("Top K · \(draft.topK)", value: $draft.topK, in: 5...100, step: 5)
                .monospacedDigit()
            Stepper("RRF k · \(rrfK)", value: Binding(
                get: { rrfK },
                set: { draft.fusion = .rrf(k: $0) }
            ), in: 10...200, step: 10)
                .monospacedDigit()

            Button("Save & Set as candidate") { saveDraftAsCandidate(id: id) }
            Button("Discard", role: .destructive) { discardDraft(id: id) }
        } header: {
            Text("DRAFT · \(draft.version)")
        } footer: {
            Text("改完之后要在 Eval Center 用同一套配置跑一次 current 与 baseline，Gate 才有东西可判。")
                .font(.footnote)
        }
    }

    // MARK: 版本列表

    @ViewBuilder
    private var versionsSection: some View {
        Section {
            ForEach(store.registry.records) { record in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.config.version).font(.subheadline)
                        Text("\(record.config.mode.rawValue) · k\(record.config.topK) · \(record.config.chunkStrategy.identity)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: AppSpacing.sm)
                    Text(record.role.rawValue)
                        .font(.caption2)
                        .foregroundStyle(roleColor(record.role))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard record.role == .draft else { return }
                    store.setCandidate(id: record.id)
                }
            }
        } header: {
            Text("VERSIONS")
        } footer: {
            Text("点一条 draft 把它设为 candidate。候选至多一条 —— 两个候选并存时「能不能上」就没有主语了。")
                .font(.footnote)
        }
    }

    private func roleColor(_ role: RetrievalConfigRecord.Role) -> Color {
        switch role {
        case .production: return .green
        case .candidate:  return .accentColor
        case .draft:      return .secondary
        }
    }

    // MARK: 阈值

    @ViewBuilder
    private var thresholdsSection: some View {
        Section {
            // R@1 是主判定指标，R@5 是 safety-net —— 判定区里它俩合成一行，
            // 这里也照同一个口径展示，免得开发者以为 Gate 只看 R@5。
            LabeledContent("Recall @1/@5",
                           value: "R@1 ≥ baseline + \(String(format: "%.3f", store.thresholds.recallAt1MinDelta))"
                                + " · R@5 ≥ baseline + \(String(format: "%.3f", store.thresholds.recallAt5MinDelta))")
                .font(.footnote)
            LabeledContent("MRR 容差", value: String(format: "%.3f", store.thresholds.mrrTolerance)).font(.footnote)
            LabeledContent("P95 预算", value: "\(Int(store.thresholds.p95BudgetMs)) ms").font(.footnote)
            LabeledContent("Regression", value: "≥ \(Int(store.thresholds.regressionPassRateMin * 100))%").font(.footnote)
        } header: {
            Text("GATE THRESHOLDS")
        } footer: {
            Text("这些是初值，不是 PRD 定值。阈值可配的意义就在这里 —— 拿到确切数字后改这一处，不用动判定逻辑。")
                .font(.footnote)
        }
    }

    // MARK: 动作

    /// `weighted` 融合没有 k —— 它在 Lab 里只作为对照存在（`RRFFusion.swift`），
    /// 这里显示默认的 60 而不是编一个数出来。
    private var rrfK: Int {
        if case let .rrf(k) = draft.fusion { return k }
        return 60
    }

    private func duplicateFromProduction() {
        guard let record = store.duplicate(from: store.registry.production.id, mutate: { _ in }) else { return }
        draftID = record.id
        draft = record.config
    }

    private func saveDraftAsCandidate(id: String) {
        // 参数改了就要换一条记录：同一个 version 底下换参数，会让 EvalRun / Trace 里
        // 记的那个字符串对不上实际跑的东西。
        //
        // 从**空壳 draft 的上游**派生，不是从空壳本身派生 —— 空壳马上就要被删掉，
        // 从它派生会留下一条指向已删记录的 `derivedFrom`，之后回溯血缘就断了。
        let parentID = store.registry.record(id: id)?.derivedFrom ?? store.registry.production.id
        guard let record = store.duplicate(from: parentID, mutate: { config in
            config.mode = draft.mode
            config.chunkStrategy = draft.chunkStrategy
            config.topK = draft.topK
            config.fusion = draft.fusion
        }) else { return }
        store.remove(id: id)          // 丢掉那个空壳 draft
        store.setCandidate(id: record.id)
        draftID = nil
    }

    private func discardDraft(id: String) {
        store.remove(id: id)
        draftID = nil
    }
}

/// `ChunkStrategy` 带关联值，`Picker` 需要一个可比较的枚举。
/// 三个选项与 `DEVTOOLS.md` §4.2 的 Picker 一一对应。
private enum ChunkStrategyOption: String, CaseIterable, Hashable {
    case block, fixed, sentence

    init(_ strategy: ChunkStrategy) {
        switch strategy {
        case .block:    self = .block
        case .fixed:    self = .fixed
        case .sentence: self = .sentence
        }
    }

    var strategy: ChunkStrategy {
        switch self {
        case .block:    return .block
        case .fixed:    return .default
        case .sentence: return .sentence(maxChars: 240)
        }
    }

    var label: String {
        switch self {
        case .block:    return "Block"
        case .fixed:    return "Block + 字数上限"
        case .sentence: return "Sentence"
        }
    }
}

#endif  // DEBUG || INTERNAL_BUILD
