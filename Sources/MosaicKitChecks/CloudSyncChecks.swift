import Foundation
import MosaicKit

/// iCloud 同步状态的口径断言。
///
/// 核心主张只有一条：**「界面说在同步」当且仅当「容器真的是 CloudKit 支撑的」。**
/// 这一条如果只写在文档里，下一次有人加一个 `@State var isSyncing` 就破了；
/// 写成 `state(...)` 的三个入参之后，那个状态在类型层面就无法被伪造。
enum CloudSyncChecks {

    static func run(_ r: CheckRunner) {
        checkNeverClaimsSyncWithoutABackingContainer(r)
        checkUnavailableBuildIsNotToggleable(r)
        checkStoredPreferenceIsSanitized(r)
        checkCopyNeverOverstates(r)
    }

    // MARK: 1 · 八种组合里只有一种能是「同步中」

    private static func checkNeverClaimsSyncWithoutABackingContainer(_ r: CheckRunner) {
        r.suite("iCloud · 只有容器真的是 CloudKit 支撑时才可能报「同步中」")

        var claimedSync = 0
        for build in [false, true] {
            for user in [false, true] {
                for backed in [false, true] {
                    let state = CloudSyncPolicy.state(buildSupportsCloudKit: build,
                                                      userEnabled: user,
                                                      containerIsCloudKitBacked: backed)
                    if state.isActuallySyncing {
                        claimedSync += 1
                        r.expect(build && user && backed,
                                 "报「同步中」的那一格必须三个条件全真（build \(build) / user \(user) / backed \(backed)）")
                    }
                }
            }
        }
        r.expectEqual(claimedSync, 1, "八种组合里，只有一种能是「同步中」")

        // 修复前的那一格：用户开了、构建也支持，但容器退回了本地。
        let degraded = CloudSyncPolicy.state(buildSupportsCloudKit: true,
                                             userEnabled: true,
                                             containerIsCloudKitBacked: false)
        r.expect(!degraded.isActuallySyncing, "退回本地时**不**报同步中")
        if case .degradedLocalOnly = degraded {
            r.expect(true, "而是一个必须显示出来的降级状态，不是静默的 off")
        } else {
            r.expect(false, "退回本地应当是 degradedLocalOnly，而不是被折叠成 off")
        }
    }

    // MARK: 2 · 没有能力的构建不给开关

    private static func checkUnavailableBuildIsNotToggleable(_ r: CheckRunner) {
        r.suite("iCloud · 构建没有 CloudKit 能力时不提供开关（DECISION_CONFIG）")

        r.expect(!CloudSyncPolicy.isUserToggleable(buildSupportsCloudKit: false),
                 "给一个必然失败的开关不是「保留功能」，是留一个陷阱")
        r.expect(CloudSyncPolicy.isUserToggleable(buildSupportsCloudKit: true),
                 "有能力时照常可开关")

        r.expect(!CloudSyncPolicy.requestsCloudKitContainer(buildSupportsCloudKit: false, userEnabled: true),
                 "没有能力时不去申请 CloudKit 容器 —— 申请一个必定失败的配置只会多一次失败重试")
        r.expect(CloudSyncPolicy.requestsCloudKitContainer(buildSupportsCloudKit: true, userEnabled: true),
                 "有能力且用户开了才申请")
        r.expect(!CloudSyncPolicy.requestsCloudKitContainer(buildSupportsCloudKit: true, userEnabled: false),
                 "用户关着就不申请")

        let state = CloudSyncPolicy.state(buildSupportsCloudKit: false, userEnabled: true,
                                          containerIsCloudKitBacked: false)
        r.expectEqual(state, .unavailableInThisBuild,
                      "构建没有能力时，用户偏好是什么都不影响结论")
    }

    // MARK: 3 · 降级安装：旧偏好不能继续说「已开启」

    private static func checkStoredPreferenceIsSanitized(_ r: CheckRunner) {
        r.suite("iCloud · 从带 CloudKit 的构建换到不带的，存下的开关值要收敛")

        r.expect(!CloudSyncPolicy.sanitizedUserPreference(true, buildSupportsCloudKit: false),
                 "旧构建存的 true 在新构建里收敛成 false")
        r.expect(CloudSyncPolicy.sanitizedUserPreference(true, buildSupportsCloudKit: true),
                 "有能力时保留用户的选择")
        r.expect(!CloudSyncPolicy.sanitizedUserPreference(false, buildSupportsCloudKit: true),
                 "关着就是关着，不会被「有能力」提上来")
    }

    // MARK: 4 · 文案不能比事实说得多

    private static func checkCopyNeverOverstates(_ r: CheckRunner) {
        r.suite("iCloud · 只有真的在同步时，文案里才允许出现「会同步」")

        for state in [CloudSyncState.unavailableInThisBuild,
                      .off,
                      .degradedLocalOnly(reason: "测试原因")] {
            let copy = state.userFacingSummary
            r.expect(copy.contains("只保存在这台设备上"),
                     "非同步状态必须明说数据只在本机（\(state)）")
            r.expect(!copy.contains("会同步到"),
                     "非同步状态的文案里不能出现同步承诺（\(state)）")
        }
        r.expect(CloudSyncState.syncing.userFacingSummary.contains("会同步到"),
                 "真的在同步时才给同步承诺")
        r.expect(CloudSyncState.degradedLocalOnly(reason: "测试原因").userFacingSummary.contains("测试原因"),
                 "降级时要带上可操作的原因，而不是只说「失败」")
    }
}
