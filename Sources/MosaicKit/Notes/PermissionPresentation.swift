import Foundation

/// # 权限被拒时的 UX（`UI_REDESIGN.md` v2 §Stage G）
///
/// `AudioRecorderService.permissionDenied` 这个状态一直存在，但 UI 从来没有消费它 ——
/// 用户看到的是一句通用的「无法开始录音」，而真正该做的事（去系统设置里打开麦克风）
/// 一个字都没提。一个被拒的权限如果不告诉用户怎么恢复，功能就等于永久坏了。
///
/// 文案与「该不该给去设置按钮」放在内核，因为这是**产品判断**，不是排版：
/// 只有「用户明确拒绝过」才该引导去设置；「还没问过」的正确动作是再问一次。
public enum PermissionKind: String, Sendable, Equatable, CaseIterable {
    case microphone
    case speechRecognition
    case photoLibrary
    case camera

    public var displayName: String {
        switch self {
        case .microphone:        return "麦克风"
        case .speechRecognition: return "语音识别"
        case .photoLibrary:      return "照片"
        case .camera:            return "相机"
        }
    }

    /// 为什么需要它。与 Info.plist 的 usage description **同一个说法** ——
    /// 系统弹窗和应用内解释说两套话会让人怀疑哪一句是真的。
    public var reason: String {
        switch self {
        case .microphone:        return "录制语音笔记需要使用麦克风。"
        case .speechRecognition: return "把录音转成文字需要语音识别权限；识别在这台设备上完成，音频不会上传。"
        case .photoLibrary:      return "把照片加入笔记需要访问相册。"
        case .camera:            return "拍照加入笔记需要使用相机。"
        }
    }
}

public struct PermissionDeniedCopy: Sendable, Equatable {
    public let title: String
    public let message: String
    /// 给不给「打开设置」。**只有明确被拒才给** —— 还没问过时正确的动作是再问一次，
    /// 把用户送去设置里找一个还不存在的开关是白跑一趟。
    public let offersSettings: Bool
    public let primaryActionTitle: String

    public init(title: String, message: String, offersSettings: Bool, primaryActionTitle: String) {
        self.title = title
        self.message = message
        self.offersSettings = offersSettings
        self.primaryActionTitle = primaryActionTitle
    }
}

public enum PermissionStatus: Sendable, Equatable {
    /// 还没问过。
    case notDetermined
    case granted
    /// 用户拒绝过，或被家长控制等策略限制。
    case denied
}

public enum PermissionPresentation {

    public static func copy(for kind: PermissionKind, status: PermissionStatus) -> PermissionDeniedCopy? {
        switch status {
        case .granted:
            return nil
        case .notDetermined:
            return PermissionDeniedCopy(
                title: "需要\(kind.displayName)权限",
                message: kind.reason,
                offersSettings: false,
                primaryActionTitle: "允许访问")
        case .denied:
            return PermissionDeniedCopy(
                title: "\(kind.displayName)权限已关闭",
                message: kind.reason + "你之前拒绝过这个权限，需要到系统设置里重新打开。",
                offersSettings: true,
                primaryActionTitle: "打开设置")
        }
    }

    /// 从设置返回之后要不要重新检查。
    ///
    /// **要。** 用户去设置里开了权限再切回来，如果界面还停在「权限已关闭」，
    /// 他会以为没生效而再去开一次。这一条写成函数是为了有断言守着它 ——
    /// 它是最容易被漏掉的一步。
    public static func shouldRecheckOnForeground(_ status: PermissionStatus) -> Bool {
        status != .granted
    }
}
