import Foundation
import MosaicKit

/// # 生产检索配置的一致性（`PRODUCTION_RETRIEVAL = KEYWORD`）
///
/// 这一组存在的理由是一次真实的不一致：文档、Gate baseline、真机基准都写着
/// 「生产走 keyword」，而 `RetrievalConfig.production` 是 `RetrievalConfig()`，
/// 初始化器的 `mode` 默认值是 `.hybrid` —— 于是**线上跑的是 hybrid**。
/// 两条路都能跑通，所以没有任何一条既有断言会因此变红。
///
/// 一致性靠人去核对是不成立的：核对一次之后，下一次改动没有人会再做第二次。
/// 所以这里把「生产是什么」写成断言。改产品决策要连着改这里 —— 那是刻意的摩擦。
enum ProductionConfigChecks {

    static func run(_ r: CheckRunner) {
        checkProductionIsKeyword(r)
        checkExperimentalArmIsNotProduction(r)
        checkRegistryRootMatchesProduction(r)
        checkRootMigration(r)
        checkCapabilityDoesNotAdvertiseAbsentSemantics(r)
        checkNoCloudUpgradeOfferWithoutSemantics(r)
    }

    // MARK: 1 · 生产就是 keyword

    private static func checkProductionIsKeyword(_ r: CheckRunner) {
        r.suite("生产检索配置 · PRODUCTION_RETRIEVAL = KEYWORD")

        let p = RetrievalConfig.production
        r.expect(p.mode == .keyword,
                 "生产 mode 是 keyword（实际 \(p.mode.rawValue)）")
        r.expect(!p.mode.usesVector,
                 "生产不走向量路 —— 语义那一整条（索引 · 查询 · 状态栏）都不该发生")
        r.expect(p.mode.usesKeyword, "生产走词法路")

        // 版本字符串会被写进每一条 Trace 与 EvalRun。它必须能自证是哪一套，
        // 否则回溯一次线上问题时只能靠记忆。
        r.expect(p.version.contains("keyword"),
                 "生产版本号自述走的是哪条路（\(p.version)）")

        // `mode` 没有默认值这件事本身要有断言守着 —— 它是防止这次不一致重演的结构性保证。
        // Swift 里无法直接断言「某个参数没有默认值」，但可以断言等价的可观察事实：
        // 两套具名配置的 mode 不同，且都不是从默认值来的。
        r.expect(RetrievalConfig.production.mode != RetrievalConfig.localHybridExperimental.mode,
                 "两套具名配置的 mode 确实不同 —— 不是同一个默认值的两个别名")
    }

    // MARK: 2 · 实验臂就是实验臂

    private static func checkExperimentalArmIsNotProduction(_ r: CheckRunner) {
        r.suite("生产检索配置 · local-hybrid 是实验臂，不是默认")

        let exp = RetrievalConfig.localHybridExperimental
        r.expect(exp.mode == .hybrid, "实验臂走 hybrid")
        r.expect(exp.mode.usesVector, "实验臂确实用向量路 —— 否则它和生产没有区别，比较无意义")
        r.expect(exp != RetrievalConfig.production,
                 "实验臂与生产不是同一套配置")
        r.expect(exp.version.contains("experimental"),
                 "实验臂版本号自述是实验（\(exp.version)）—— Trace 里看到它就知道那不是线上")
    }

    // MARK: 3 · 注册表的根记录 = 编译期生产

    private static func checkRegistryRootMatchesProduction(_ r: CheckRunner) {
        r.suite("生产检索配置 · 注册表根记录")

        let registry = RetrievalConfigRegistry()
        r.expect(registry.productionConfig == RetrievalConfig.production,
                 "新建注册表的生产记录就是 `RetrievalConfig.production`")
        r.expect(registry.productionConfig.mode == .keyword,
                 "因此 App 首次启动时索引服务拿到的是 keyword")
        r.expect(registry.production.promotedAt == nil,
                 "根记录没有 promotedAt —— 它是初始值，不是被 promote 上去的")
    }

    // MARK: 4 · 老设备上落盘的注册表要能迁移

    private static func checkRootMigration(_ r: CheckRunner) {
        r.suite("生产检索配置 · 落盘注册表的迁移")

        // ① 老的根记录（hybrid）→ 迁移到当前生产（keyword）。
        //    这是真实场景：上一版 App 在这台手机上写下了 hybrid 的根记录。
        var stale = RetrievalConfigRegistry(production: RetrievalConfig(version: "retrieval-v1",
                                                                       mode: .hybrid))
        r.expect(stale.productionConfig.mode == .hybrid, "前置：落盘的是 hybrid")
        let didMigrate = stale.migrateRootProduction(to: .production)
        r.expect(didMigrate, "迁移发生了")
        r.expect(stale.productionConfig == RetrievalConfig.production,
                 "迁移后线上跑的与代码/文档一致（\(stale.productionConfig.version)）")
        r.expect(stale.records.count == 1, "迁移是替换根记录，不是追加一条")

        // ② 已经是当前生产 → 不动，也不重复落盘。
        var fresh = RetrievalConfigRegistry()
        r.expect(!fresh.migrateRootProduction(to: .production),
                 "已经一致时不迁移 —— 每次启动都写一次盘是无谓的磨损")

        // ③ **经 Gate Promote 上线过的配置不动。** 这是这条迁移唯一的危险面：
        //    一次 App 更新不能悄悄改掉一个有记录的人为决定。
        var promoted = RetrievalConfigRegistry()
        let candidate = try! promoted.duplicate(from: promoted.production.id) { $0.mode = .hybrid }
        try! promoted.setCandidate(id: candidate.id)
        let pass = GateDecision(status: .pass,
                                configVersion: candidate.config.version,
                                evaluatedAt: Date(),
                                checks: [])
        _ = try! promoted.promote(id: candidate.id, decision: pass)
        r.expect(promoted.productionConfig.mode == .hybrid, "前置：hybrid 是被 promote 上去的")
        r.expect(!promoted.migrateRootProduction(to: .production),
                 "promote 过的生产配置不被迁移覆盖")
        r.expect(promoted.productionConfig.mode == .hybrid,
                 "它仍然在线上 —— 要换回去得再走一次 Promote，而不是靠一次 App 更新")
    }

    // MARK: 5 · 没承诺过的能力不存在「不可用」

    private static func checkCapabilityDoesNotAdvertiseAbsentSemantics(_ r: CheckRunner) {
        r.suite("生产检索配置 · 状态栏不谈论不存在的能力")

        // 生产是纯词法时，无论本机有没有句向量模型、索引是什么状态，
        // 用户看到的都应该是 `.full`：没有任何东西坏掉。
        for state in [IndexState.ready,
                      .building(progress: 0.3),
                      .rebuilding(pending: 5),
                      .stale(pending: 5),
                      .failed(reason: "本机没有中文句向量模型")] {
            for hasProvider in [true, false] {
                let cap = RetrievalCapability.derive(indexState: state,
                                                     semanticProviderAvailable: hasProvider,
                                                     semanticInProduction: false)
                r.expect(cap == .full,
                         "纯词法生产 · \(state) · provider=\(hasProvider) → full（实际 \(cap.rawValue)）")
            }
        }

        // 离线同样不该报 `.offline`：词法路不用网。
        r.expect(RetrievalCapability.derive(indexState: .ready,
                                            semanticProviderAvailable: false,
                                            semanticInProduction: false,
                                            offline: true) == .full,
                 "纯词法生产 · 离线 → full（词法路是纯本地的）")

        // 反向：生产**含**语义路时，旧行为逐条不变 —— 这条迁移不能顺手改掉别的判定。
        r.expect(RetrievalCapability.derive(indexState: .ready,
                                            semanticProviderAvailable: false,
                                            semanticInProduction: true) == .semanticUnavailable,
                 "含语义路的生产下，缺 provider 仍报 semanticUnavailable")
        r.expect(RetrievalCapability.derive(indexState: .building(progress: 0.1),
                                            semanticProviderAvailable: true,
                                            semanticInProduction: true) == .indexBuilding,
                 "含语义路的生产下，建索引仍报 indexBuilding")
        r.expect(RetrievalCapability.derive(indexState: .ready,
                                            semanticProviderAvailable: true) == .full,
                 "默认参数保持旧含义（含语义路）—— 既有调用点行为不变")
    }

    // MARK: 6 · 不推销一个开了也没用的开关

    private static func checkNoCloudUpgradeOfferWithoutSemantics(_ r: CheckRunner) {
        r.suite("生产检索配置 · 纯词法生产下不提示「开启云端智能搜索」")

        // 四个前置条件全部满足的那一刻 —— 本地路线 · 云端已配 · 尚未授权 · 双语库。
        // 在含语义路的生产下这正是该提示的时候。
        func offer(semanticInProduction: Bool) -> Bool {
            EmbeddingRouter.shouldOfferCloudUpgrade(route: .localEnglish,
                                                    cloudConfigured: true,
                                                    cloudConsentGranted: false,
                                                    corpusContainsHan: true,
                                                    corpusContainsLatin: true,
                                                    semanticInProduction: semanticInProduction)
        }

        r.expect(offer(semanticInProduction: true),
                 "前置：含语义路的生产下，这一刻确实该提示（否则下面那条断言证明不了什么）")
        r.expect(!offer(semanticInProduction: false),
                 "纯词法生产下不提示 —— 用户照着开了云端，搜索行为一点不变，"
                 + "而代价是授权一次把笔记文字发到第三方")
        r.expect(!EmbeddingRouter.shouldOfferCloudUpgrade(
                    route: .localChinese, cloudConfigured: true, cloudConsentGranted: false,
                    corpusContainsHan: true, corpusContainsLatin: true,
                    semanticInProduction: RetrievalConfig.production.mode.usesVector),
                 "拿**当前**生产配置去问同样得到「不提示」")
    }
}
