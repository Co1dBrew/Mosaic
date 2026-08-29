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

/// # D7 / D8 —— Release Gate（backlog 5.3 / 5.4）
///
/// **要求：进入页面 2 秒内答出「能不能上」和「为什么不能」**（`DEVTOOLS.md` §4.7）。
/// 所以版式是固定的：顶部一整块判定区（34pt 加粗），下面四行检查，
/// 每行给出**具体条件与实测值** —— 只给 ❌ 而不给「310 ms > 250 ms」的 Gate
/// 答不出第二个问题。
///
/// 失败行整行红底，并给 `Open Failures ›` 直达 D9：从「不能上线」到「为什么」
/// 只需一次点击。
struct ReleaseGateView: View {

    @State var viewModel: ReleaseGateViewModel
    /// D9 的数据源。Gate 与 Eval Center 共用**同一个** eval ViewModel ——
    /// 各自持有一份的话，Gate 上看到的失败会和 Eval 里刚标注过的那批对不上。
    let eval: RetrievalEvalViewModel?

    var body: some View {
        List {
            verdictSection
            checksSection
            configSection
            promoteSection
            explanation
        }
        .navigationTitle("Release Gate")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Promote", isPresented: Binding(
            get: { viewModel.banner != nil },
            set: { if !$0 { viewModel.dismissBanner() } }
        )) {
            Button("好") { viewModel.dismissBanner() }
        } message: { Text(viewModel.banner ?? "") }
    }

    // MARK: 判定区

    @ViewBuilder
    private var verdictSection: some View {
        Section {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(viewModel.decision.headline)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(verdictForeground)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(viewModel.verdictDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppSpacing.sm)
            .listRowBackground(verdictBackground)
        }
    }

    private var verdictForeground: Color {
        switch viewModel.decision.status {
        case .pass:    return .green
        case .blocked: return .red
        case .stale:   return .orange
        }
    }

    private var verdictBackground: Color {
        switch viewModel.decision.status {
        case .pass:    return Color.green.opacity(0.12)
        case .blocked: return Color.red.opacity(0.12)
        case .stale:   return Color.orange.opacity(0.12)
        }
    }

    // MARK: 四项检查

    @ViewBuilder
    private var checksSection: some View {
        Section {
            if viewModel.checks.isEmpty {
                Text("还没有可判定的评测结果。去 Eval Center 跑一次 current，再跑一次 baseline。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(viewModel.checks) { check in
                checkRow(check)
            }
        } header: {
            Text("CHECKS")
        } footer: {
            Text("判定 = 四项全过。**不做加权、不做总分** —— 加权会制造「大部分指标都很好」的错觉，而拦住这种错觉正是 Gate 存在的意义。")
                .font(.footnote)
        }
    }

    @ViewBuilder
    private func checkRow(_ check: GateCheck) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(check.kind.label).font(.subheadline.weight(.medium))
                Spacer(minLength: AppSpacing.sm)
                Text(check.actualText).monospacedDigit()
                Text(check.conditionText).font(.caption).foregroundStyle(.secondary)
                Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(check.passed ? Color.green : Color.red)
            }
            if let detail = check.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 失败行直达 D9。只有质量类检查有失败用例可看 —— P95 超预算不对应任何一条 case。
            if check.opensFailures, let eval, !eval.failures.isEmpty {
                NavigationLink {
                    FailureListView(viewModel: eval,
                                    restrictToRegression: check.kind == .regression)
                } label: {
                    Text("Open Failures").font(.caption.weight(.medium))
                }
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(check.passed ? Color.clear : Color.red.opacity(0.10))
    }

    // MARK: 配置与跑批出处

    @ViewBuilder
    private var configSection: some View {
        Section("EVALUATED CONFIG") {
            LabeledContent("Version", value: viewModel.target.config.version)
            LabeledContent("Role", value: viewModel.target.role.rawValue)
            LabeledContent("Mode", value: viewModel.target.config.mode.rawValue)
            LabeledContent("Chunk", value: viewModel.target.config.chunkStrategy.identity).font(.footnote)
            LabeledContent("Top K", value: "\(viewModel.target.config.topK)").monospacedDigit()
            LabeledContent("Production", value: viewModel.productionRecord.config.version)
                .foregroundStyle(.secondary)
        }

        Section("EVIDENCE") {
            runRow("Current", run: viewModel.currentRun)
            runRow("Baseline", run: viewModel.baselineRun)
            LabeledContent("P95 Budget", value: "\(Int(viewModel.thresholds.p95BudgetMs)) ms")
            LabeledContent("Regression ≥", value: "\(Int(viewModel.thresholds.regressionPassRateMin * 100))%")
        }
    }

    @ViewBuilder
    private func runRow(_ label: String, run: EvalRun?) -> some View {
        if let run {
            LabeledContent(label,
                           value: "\(run.configVersion) · \(run.metrics.caseCount) cases")
                .font(.footnote)
        } else {
            LabeledContent(label, value: "—").font(.footnote).foregroundStyle(.orange)
        }
    }

    // MARK: Promote

    @ViewBuilder
    private var promoteSection: some View {
        Section {
            Button("Promote to Production") { viewModel.promote() }
                .disabled(!viewModel.canPromote)
        } footer: {
            Text(viewModel.canPromote
                 ? "写入 promotedAt，并让索引服务改用这套配置（换了 chunk 策略会触发重建）。"
                 : "BLOCKED / STALE 时不可用。界面置灰只是呈现 —— 真正的拦截在注册表里，它不接受非 PASS 的判定。")
                .font(.footnote)
        }
    }

    @ViewBuilder
    private var explanation: some View {
        Section {
            Text("Eval 只讲 trade-off，不下 PASS / FAIL；判定只在这里发生。两个地方都能说 PASS 的系统，最后总有一个地方说了算，而那个地方不会是文档写的那个。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

#endif  // DEBUG || INTERNAL_BUILD
