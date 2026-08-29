import SwiftUI
import MosaicKit

/// # 笔记页顶部的 AI 摘要条（`UI_REDESIGN.md` v2 §3.4）
///
/// 收起态是一条 44pt 横条；展开在**原地**进行，不跳页。
///
/// 相比旧的 `SummaryStickerView`，展开态从「6 个可点控件 + 3 个弹窗」降到
/// 「主题 chips + 1 个折叠器」：
///
/// - 「立即更新」「重新生成」「清除」三个常驻按钮 → 全部移进笔记页的 `⋯`
/// - 「把主题加为标签」这个独立按钮 → **删除**；主题 chip 本身可点，点一下即加为标签
/// - 模型 / 时间从独占一行改为与「初始总结」同行右对齐
/// - 更新记录 ≥2 条时二级折叠，只展开最新一条
struct NoteSummaryBarView: View {
    let state: NoteSummaryBarState
    @Binding var isExpanded: Bool
    let summary: AISummaryEntity?
    let onRetry: () -> Void
    let onAddTopicAsTag: (String) -> Void
    /// 配置类错误（缺 Key / Base URL 不对）时的「去设置」。判断在
    /// `AIError.isConfiguration`，不在这里重写 —— 每个消费错误的界面各写一遍
    /// 迟早会不一致。
    var onOpenSettings: (() -> Void)? = nil

    var body: some View {
        if case .hidden = state {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                collapsedBar
                if isExpanded, let summary, summary.hasBase {
                    expanded(summary)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.md)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
        }
    }

    // MARK: 收起态

    private var collapsedBar: some View {
        HStack(spacing: AppSpacing.sm) {
            icon
            if let text = NoteSummaryPresentation.collapsedText(state) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
            }
            Spacer(minLength: AppSpacing.sm)
            trailing
        }
        .padding(.horizontal, AppSpacing.lg)
        .frame(height: AppMetrics.minTapTarget)
        .contentShape(Rectangle())
        .onTapGesture {
            guard state.isExpandable else { return }
            isExpanded.toggle()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("note.summaryBar")
        .accessibilityAddTraits(state.isExpandable ? .isButton : [])
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .failed:
            Image(systemName: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        default:
            Image(systemName: "sparkles").font(.caption).foregroundStyle(.tint)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .generating:
            ProgressView().controlSize(.small)
        case .failed(_, let opensSettings):
            if opensSettings, let onOpenSettings {
                Button("去设置", action: onOpenSettings).font(.footnote)
            } else {
                Button("重试", action: onRetry).font(.footnote)
            }
        case .ready(_, let hasUnread):
            if hasUnread {
                Circle().fill(.red).frame(width: 7, height: 7)
                    .accessibilityLabel("有未读的更新总结")
            }
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption2).foregroundStyle(.secondary)
        case .hidden, .pending:
            EmptyView()
        }
    }

    private var textColor: Color {
        switch state {
        case .pending:  return .secondary
        case .failed:   return .primary
        default:        return .primary
        }
    }

    // MARK: 展开态

    private func expanded(_ summary: AISummaryEntity) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("初始总结").font(.caption).bold().foregroundStyle(.secondary)
                Spacer()
                // 模型与时间和标题同行右对齐 —— 它们是元数据，不值一整行。
                Text("\(summary.baseModelUsed) · \(Format.dateTime(summary.baseGeneratedAt))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            if !summary.baseType.isEmpty {
                Text(summary.baseType)
                    .font(.caption2).bold()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            if !summary.baseTopics.isEmpty {
                // 主题 chip **可点即加为标签**。一次一个，即时反馈 ——
                // 旧版是一个「把主题加为标签」按钮，一次全加，加错了要一个个删。
                FlowLayout(spacing: AppSpacing.xs) {
                    ForEach(summary.baseTopics, id: \.self) { topic in
                        Button { onAddTopicAsTag(topic) } label: {
                            TagChip(text: topic)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("点按加为标签")
                    }
                }
            }

            if !summary.baseKeyPoints.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(summary.baseKeyPoints, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Text(point).font(.subheadline)
                        }
                    }
                }
            }

            if !summary.baseSummary.isEmpty {
                Text(summary.baseSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let logs = summary.sortedUpdateLogs
            if !logs.isEmpty {
                Divider()
                UpdateLogsSection(logs: logs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 更新记录：**≥2 条时二级折叠，只展开最新一条**。
/// 平铺全部会把一页变成一份变更日志，而用户关心的通常只是最近发生了什么。
private struct UpdateLogsSection: View {
    let logs: [UpdateLogEntity]
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("更新记录 (\(logs.count))")
                    .font(.caption).bold().foregroundStyle(.secondary)
                Spacer()
                if logs.count > 1 {
                    Button(showAll ? "收起" : "展开全部") { showAll.toggle() }
                        .font(.caption2)
                }
            }
            ForEach(showAll ? logs : Array(logs.prefix(1))) { log in
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.updateOneLiner).font(.subheadline)
                    ForEach(log.changes, id: \.self) { change in
                        Text("· \(change)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(Format.dateTime(log.generatedAt))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}
