import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// # iCloud 状态不能说谎
///
/// 内核那一侧（`CloudSyncChecks`）测的是**口径**：哪一组输入才允许报「同步中」。
/// 这一组测的是**接线**：这个构建的实际能力、容器实际建成了什么、
/// 以及设置里的偏好会不会被收敛。
///
/// 之所以要分两处：口径写对了但没接上，UI 照样会说谎。
@MainActor
final class CloudSyncTruthfulnessTests: XCTestCase {

    /// 仓库当前状态：`Mosaic.entitlements` 是空的 `<dict/>`，
    /// `project.yml` 里 `MOSAIC_CLOUDKIT_ENABLED = NO`。
    ///
    /// 这条用例是**故意**跟着构建配置走的：哪天真的加上了 CloudKit 能力，
    /// 它会失败，提醒把 entitlements / 容器 / 手工验证一起做完再改断言。
    func testThisBuildDeclaresNoCloudKitCapability() {
        XCTAssertFalse(ModelContainerFactory.buildSupportsCloudKit,
                       "entitlements 里没有 iCloud 容器，构建能力必须如实为 false")
    }

    func testUIStateMatchesRealPersistenceState() {
        let store = ModelContainerFactory.makeNoteStore(
            cloudKitRequested: CloudSyncPolicy.requestsCloudKitContainer(
                buildSupportsCloudKit: ModelContainerFactory.buildSupportsCloudKit,
                userEnabled: true),
            inMemory: true)
        let state = CloudSyncPolicy.state(
            buildSupportsCloudKit: ModelContainerFactory.buildSupportsCloudKit,
            userEnabled: true,
            containerIsCloudKitBacked: store.isCloudKitBacked)

        XCTAssertEqual(state.isActuallySyncing, store.isCloudKitBacked,
                       "界面状态与容器事实必须一致 —— 这就是这次修复的全部主张")
        XCTAssertFalse(state.isActuallySyncing, "当前构建下不可能在同步")
    }

    /// 容器**没有** CloudKit 支撑时，绝不能报同步中 —— 即使用户偏好是开着的。
    func testLocalFallbackNeverReportsSyncing() {
        let state = CloudSyncPolicy.state(buildSupportsCloudKit: true,
                                          userEnabled: true,
                                          containerIsCloudKitBacked: false)
        XCTAssertFalse(state.isActuallySyncing)
        XCTAssertTrue(state.userFacingSummary.contains("只保存在这台设备上"))
    }

    /// 设置里把开关打开：在没有能力的构建里必须**弹回**关闭。
    /// 否则界面会显示「已开启」，而数据一直在本机。
    func testTogglingOnIsRefusedWhenTheBuildCannotSync() {
        let defaults = UserDefaults(suiteName: "cloud-sync-test-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults, keychain: InMemoryKeychain())
        XCTAssertFalse(settings.iCloudSyncEnabled)

        settings.iCloudSyncEnabled = true

        XCTAssertEqual(settings.iCloudSyncEnabled, ModelContainerFactory.buildSupportsCloudKit,
                       "构建没有能力时，写入 true 会被收敛回 false")
        XCTAssertFalse(defaults.bool(forKey: "settings.iCloudSyncEnabled"),
                       "落盘的值同样不能是 true —— 否则下次启动又会显示已开启")
    }
}
