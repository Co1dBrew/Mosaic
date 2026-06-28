import SwiftUI
import UIKit
import MosaicKit

/// The AI summary sticker (PRD §4.5): base summary (preserved) + append-only
/// update logs (newest first), with loading / error / retry / empty states and
/// the first-use privacy gate.
struct SummaryStickerView: View {
    let card: Card

    @Environment(\.summaryService) private var summaryService
    @Environment(SettingsStore.self) private var settings

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var errorRetryable = false
    @State private var errorIsConfig = false
    @State private var notice: String?
    @State private var showPrivacy = false
    @State private var pendingAction: (() -> Void)?
    @State private var showRegenerateConfirm = false
    @State private var showClearConfirm = false
    @State private var lastRetry: (() -> Void)?

    private var summary: AISummaryEntity? { card.summary }
    private var hasBase: Bool { summary?.hasBase ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                loadingView
            } else if let errorMessage {
                errorView(errorMessage)
            } else if hasBase, let summary {
                baseSummaryView(summary)
                if !summary.sortedUpdateLogs.isEmpty {
                    Divider()
                    updateLogsView(summary)
                }
                actionButtons
            } else {
                emptyOrPromptView
            }

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: onAppear)
        .alert("隐私提示", isPresented: $showPrivacy) {
            Button("取消", role: .cancel) { pendingAction = nil }
            Button("同意并继续") {
                settings.hasAcceptedAIPrivacyNotice = true
                let action = pendingAction
                pendingAction = nil
                action?()
            }
        } message: {
            Text("生成总结会把这张卡片的文字内容与图片,通过 HTTPS 发送到你在「设置」中选择的第三方 AI 服务商。原始录音不会上传(改用本地转写文字)。调用费用由你的 API Key 账户承担。")
        }
        .confirmationDialog("重新生成完整总结?", isPresented: $showRegenerateConfirm, titleVisibility: .visible) {
            Button("重新生成", role: .destructive) { gate { regenerate() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清空当前的初始总结与全部更新记录,并重新生成。")
        }
        .confirmationDialog("清除此卡片的 AI 摘要?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                summaryService?.clearSummary(for: card)
                errorMessage = nil; notice = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除初始总结与全部更新记录(不会重新生成),不影响卡片内容。")
        }
    }

    // MARK: Subviews

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("AI 正在总结…").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.primary)
            HStack(spacing: 12) {
                if errorRetryable {
                    Button("重试") { lastRetry?() }
                        .buttonStyle(.borderedProminent)
                }
                if errorIsConfig {
                    NavigationLink("去设置") { SettingsView() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var emptyOrPromptView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("还没有 AI 总结")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                gate { generateBase() }
            } label: {
                Label("生成总结", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func baseSummaryView(_ summary: AISummaryEntity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("初始总结")
                .font(.caption).bold().foregroundStyle(.secondary)

            if !summary.baseType.isEmpty {
                Text(summary.baseType)
                    .font(.caption2).bold()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            if !summary.baseTopics.isEmpty {
                FlowChips(items: summary.baseTopics)
            }

            if !summary.baseKeyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(summary.baseKeyPoints.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Text(point).font(.subheadline)
                        }
                    }
                }
            }

            if !summary.baseSummary.isEmpty {
                Text(summary.baseSummary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            Text("\(summary.baseProviderUsed) · \(summary.baseModelUsed) · \(Format.dateTime(summary.baseGeneratedAt))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func updateLogsView(_ summary: AISummaryEntity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("更新记录")
                .font(.caption).bold().foregroundStyle(.secondary)
            ForEach(summary.sortedUpdateLogs) { log in
                VStack(alignment: .leading, spacing: 4) {
                    Text(log.updateOneLiner.isEmpty ? "内容有更新" : log.updateOneLiner)
                        .font(.subheadline).bold()
                    ForEach(Array(log.changes.enumerated()), id: \.offset) { _, change in
                        HStack(alignment: .top, spacing: 6) {
                            Text("·").foregroundStyle(.secondary)
                            Text(change).font(.caption)
                        }
                    }
                    Text(Format.dateTime(log.generatedAt))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button { gate { update() } } label: {
                Label("立即更新", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.caption)
            Button { showRegenerateConfirm = true } label: {
                Label("重新生成", systemImage: "sparkles")
            }
            .font(.caption)
            Button(role: .destructive) { showClearConfirm = true } label: {
                Label("清除", systemImage: "trash")
            }
            .font(.caption)
            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.top, 4)
    }

    // MARK: Actions

    private func onAppear() {
        markLogsRead()
        ensureBaseIfNeeded(force: false)
    }

    private func markLogsRead() {
        guard let summary, !summary.sortedUpdateLogs.isEmpty else { return }
        var changed = false
        for log in summary.updateLogs ?? [] where !log.isRead { log.isRead = true; changed = true }
        if changed { try? card.modelContext?.save() }
    }

    /// First expand auto-generates the base summary (PRD §4.5 trigger). Does not
    /// re-prompt privacy on a passive appear unless the user already accepted.
    private func ensureBaseIfNeeded(force: Bool) {
        guard !hasBase, !isLoading else { return }
        if settings.hasAcceptedAIPrivacyNotice {
            generateBase()
        } else if force {
            gate { generateBase() }
        }
        // If not accepted and not forced, show the "生成总结" prompt button instead.
    }

    /// Runs `action`, first showing the privacy notice if not yet accepted.
    private func gate(_ action: @escaping () -> Void) {
        if settings.hasAcceptedAIPrivacyNotice {
            action()
        } else {
            pendingAction = action
            showPrivacy = true
        }
    }

    private func generateBase() {
        run { service in try await service.generateBaseSummary(for: card); return true }
    }

    private func regenerate() {
        run { service in try await service.regenerateFullSummary(for: card); return true }
    }

    private func update() {
        run(noChangeNotice: "没有检测到内容变化。") { service in
            try await service.generateUpdateSummary(for: card, force: true)
        }
    }

    /// Single runner that manages loading/error/notice state. `body` returns a
    /// Bool: `false` means "nothing changed" and shows `noChangeNotice`.
    private func run(
        noChangeNotice: String? = nil,
        _ body: @escaping (SummaryService) async throws -> Bool
    ) {
        guard let summaryService else {
            setError(AIError.requestFailed(message: "服务不可用"))
            return
        }
        lastRetry = { run(noChangeNotice: noChangeNotice, body) }
        notice = nil
        errorMessage = nil
        isLoading = true
        Task { @MainActor in
            do {
                let didChange = try await body(summaryService)
                isLoading = false
                if !didChange, let noChangeNotice { notice = noChangeNotice }
            } catch let error as AIError {
                isLoading = false
                setError(error)
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
                errorRetryable = true
                errorIsConfig = false
            }
        }
    }

    private func setError(_ error: AIError) {
        errorMessage = error.userMessage
        errorRetryable = error.isRetryable
        switch error {
        case .missingAPIKey, .missingModel, .invalidBaseURL, .unauthorized:
            errorIsConfig = true
        default:
            errorIsConfig = false
        }
    }
}

/// A simple wrapping chip layout for topic keywords (PRD §4.5 主题关键词 chips).
struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlexibleWrap(items: items) { item in
            Text(item)
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Capsule())
        }
    }
}
