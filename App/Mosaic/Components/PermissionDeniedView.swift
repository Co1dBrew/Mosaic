import SwiftUI
import UIKit
import MosaicKit

/// 权限被拒时的统一界面（`UI_REDESIGN.md` v2 Stage G）。
///
/// 三个动作：**解释 · 打开设置 · 取消**，外加「从设置回来后自动重试」。
/// 文案与「给不给去设置按钮」的判断在内核 `PermissionPresentation` 里。
struct PermissionDeniedView: View {
    let kind: PermissionKind
    let status: PermissionStatus
    /// 「允许访问」（还没问过）时调用；被拒时这个按钮变成「打开设置」，不走这里。
    let onRequest: () -> Void
    let onCancel: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    private var copy: PermissionDeniedCopy? {
        PermissionPresentation.copy(for: kind, status: status)
    }

    var body: some View {
        if let copy {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(copy.title)
                    .font(.headline)
                Text(copy.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: AppSpacing.sm) {
                    PrimaryActionButton(title: copy.primaryActionTitle,
                                        systemImage: copy.offersSettings ? "gear" : "checkmark") {
                        if copy.offersSettings { openSettings() } else { onRequest() }
                    }
                    Button("取消", action: onCancel)
                        .buttonStyle(SecondaryActionButtonStyle())
                }
            }
            .padding(AppSpacing.xl)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("permission.denied.\(kind.rawValue)")
            // 从系统设置切回来时重新检查。不做这一步的话，用户开了权限回来看到的
            // 还是「权限已关闭」，会以为没生效而再去开一次。
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active,
                      PermissionPresentation.shouldRecheckOnForeground(status) else { return }
                onRequest()
            }
        }
    }

    private var icon: String {
        switch kind {
        case .microphone:        return "mic.slash"
        case .speechRecognition: return "waveform.slash"
        case .photoLibrary:      return "photo.on.rectangle.angled"
        case .camera:            return "camera"
        }
    }

    /// 系统设置里本 App 的页面。`UIApplication.openSettingsURLString` 是官方入口，
    /// 不要自己拼 `prefs:` scheme —— 那个在 App Store 审核里会被拒。
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
