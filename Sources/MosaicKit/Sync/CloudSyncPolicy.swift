import Foundation

/// # iCloud 同步的**真实**状态
///
/// ## 修的是哪一种谎
///
/// 之前的形态是一个普通的 `Toggle`：
///
/// ```
/// 用户打开「启用 iCloud 同步」
///   ↓ 构建里没有 iCloud entitlement（仓库里的 Mosaic.entitlements 是空的 <dict/>）
///   ↓ 带 CloudKit 的 ModelConfiguration 失败
///   ↓ 静默退回本地 store
///   ↓ **开关还是开着的**
/// ```
///
/// 用户由此相信笔记有云端副本。这是所有 UI 谎言里代价最高的一种 —— 它在换手机、
/// 手机丢了、或者误删之后才会被发现，而那时数据已经没了。
///
/// ## 结构性保证：状态由**事实**推导，不是被 set 出来的
///
/// `state(...)` 的三个入参分别是「这个构建有没有能力」「用户想不想开」
/// 「容器实际上是不是 CloudKit 支撑的」。**只有第三个为真时才可能返回 `.syncing`**。
/// 于是「开关说开着、其实存在本地」这个状态在类型层面就无法表达 —— 它变成了
/// `.degradedLocalOnly`，一个必须显示出来的状态。
///
/// 与 `IndexState` 是同一个套路：可以被 set 的状态字段迟早会卡住。
public enum CloudSyncState: Sendable, Equatable {

    /// 这个构建根本没有 CloudKit 能力（没有 entitlement / 没有容器）。
    /// **用户不可开启** —— 给一个必然失败的开关不是「保留功能」，是留一个陷阱。
    case unavailableInThisBuild

    /// 有能力，用户没开。
    case off

    /// 有能力、用户开了、容器**确实**是 CloudKit 支撑的。
    case syncing

    /// 用户开了，但容器退回了本地。**必须如实显示，不能装作在同步。**
    case degradedLocalOnly(reason: String)

    /// 数据到底有没有离开这台设备。UI 文案与测试都读这一个。
    public var isActuallySyncing: Bool { self == .syncing }

    /// 用户侧一行说明。不出现 CloudKit / container / entitlement 这些词 ——
    /// 它们对用户没有意义，但「笔记只存在这台设备上」有。
    public var userFacingSummary: String {
        switch self {
        case .unavailableInThisBuild:
            return "此版本不提供 iCloud 同步，笔记只保存在这台设备上。"
        case .off:
            return "已关闭。笔记只保存在这台设备上。"
        case .syncing:
            return "已开启。笔记会同步到你的 iCloud。"
        case .degradedLocalOnly(let reason):
            return "无法同步，笔记只保存在这台设备上。\(reason)"
        }
    }
}

public enum CloudSyncPolicy {

    /// 这次启动**要不要**向 SwiftData 申请 CloudKit 支撑的容器。
    ///
    /// 构建没有能力时一律不申请：申请一个必定失败的配置，唯一的效果是多一条
    /// 启动日志和一次失败重试。
    public static func requestsCloudKitContainer(buildSupportsCloudKit: Bool,
                                                 userEnabled: Bool) -> Bool {
        buildSupportsCloudKit && userEnabled
    }

    /// 由事实推导状态。
    ///
    /// - Parameter buildSupportsCloudKit: 这个构建有没有 iCloud entitlement 与容器。
    ///   来自 Info.plist 的 `MosaicCloudKitEnabled`，由 `project.yml` 一处控制 ——
    ///   与 entitlements 文件必须一起改，所以两者不会各自漂移。
    /// - Parameter userEnabled: 设置里的开关。
    /// - Parameter containerIsCloudKitBacked: `ModelContainerFactory` 实际建出来的
    ///   容器是不是带 CloudKit 的。**这是唯一能证明「真的在同步」的输入。**
    public static func state(buildSupportsCloudKit: Bool,
                             userEnabled: Bool,
                             containerIsCloudKitBacked: Bool) -> CloudSyncState {
        guard buildSupportsCloudKit else { return .unavailableInThisBuild }
        guard userEnabled else { return .off }
        guard containerIsCloudKitBacked else {
            return .degradedLocalOnly(reason: "请检查是否已登录 iCloud 且有可用空间，然后重启 App。")
        }
        return .syncing
    }

    /// 用户能不能改这个开关。
    public static func isUserToggleable(buildSupportsCloudKit: Bool) -> Bool {
        buildSupportsCloudKit
    }

    /// 把一个**存下来的**开关值收敛到这个构建允许的取值。
    ///
    /// 场景：用户在一个带 CloudKit 的构建里开过，然后装了不带的构建。
    /// 存的偏好还是 `true`，而这个构建做不到 —— 不收敛的话 UI 会继续显示「已开启」。
    public static func sanitizedUserPreference(_ stored: Bool,
                                               buildSupportsCloudKit: Bool) -> Bool {
        buildSupportsCloudKit && stored
    }
}
