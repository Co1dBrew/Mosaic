#if DEBUG
import SwiftUI

/// A DEBUG-only visual gallery of the shared UI components, shown when the app is
/// launched with the `--ui-gallery` argument. Lets us screenshot the unified
/// buttons / layout without navigating. Never shown in normal runs or release.
struct DebugGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                group("Primary (full width, centered)") {
                    PrimaryActionButton(title: "生成总结", systemImage: "sparkles") {}
                }
                group("Sticker actions (FlowLayout, wraps)") {
                    FlowLayout(spacing: AppSpacing.sm) {
                        SecondaryActionButton(title: "立即更新", systemImage: "arrow.triangle.2.circlepath") {}
                        SecondaryActionButton(title: "重新生成", systemImage: "sparkles") {}
                        DestructiveActionButton(title: "清除", systemImage: "trash") {}
                    }
                }
                group("Error + retry") {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Label("API Key 无效或无权限,请前往「设置」检查 Key。", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                        FlowLayout(spacing: AppSpacing.sm) {
                            SecondaryActionButton(title: "重试", systemImage: "arrow.clockwise") {}
                            SecondaryActionButton(title: "去设置", systemImage: "gearshape") {}
                        }
                    }
                    .appCard(background: Color(.tertiarySystemBackground))
                }
                group("Faux collapsed card bar") {
                    fauxCardBar
                }
                group("Secondary full width") {
                    SecondaryActionButton(title: "测试连接", systemImage: "bolt.horizontal", fullWidth: true) {}
                }
            }
            .padding(AppSpacing.lg)
        }
        .navigationTitle("UI Gallery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title).appSectionLabel()
            content()
        }
    }

    private var fauxCardBar: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("周三产品评审会要点").font(.headline).lineLimit(1)
                Text("记录了本周产品评审会的主要结论与待办分工。")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: AppSpacing.sm) {
                    ForEach(["text.alignleft", "waveform", "photo.fill", "link"], id: \.self) {
                        Image(systemName: $0).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("2小时前").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            ZStack(alignment: .topTrailing) {
                Image(systemName: "chevron.right").font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: AppMetrics.minTapTarget, height: AppMetrics.minTapTarget)
                Circle().fill(.red).frame(width: 9, height: 9).offset(x: -4, y: 6)
            }
        }
        .appCard()
    }
}
#endif
