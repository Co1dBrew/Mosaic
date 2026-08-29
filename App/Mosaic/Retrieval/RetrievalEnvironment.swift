import Foundation
import SwiftUI
import SwiftData
import Observation
import MosaicKit

/// 检索栈的持有者，注入给 Developer Tools。
///
/// 只有 `RetrievalTraceRecorder` 是**无条件**存在的（SLO 需要在真实用户路径上
/// 采集，`DECISION_LOG.md` D-UI-DEV-012）；其余在 Developer Mode 关闭时不会被触达。
@Observable
@MainActor
final class RetrievalEnvironment {
    /// 当前路线选中的 provider。`nil` = 语义不可用。**不退回 mock**。
    private(set) var provider: (any EmbeddingProvider)?
    /// 为什么选了这一路。Developer Mode 原样展示。
    private(set) var route: EmbeddingRoute
    let vectors: InMemoryVectorStore
    let recorder: RetrievalTraceRecorder
    let derived: DerivedDataStore
    /// Golden / Regression Set。**不放 derived store** —— 那里的契约是「可以随时清空」，
    /// 而人工标注的用例删了就得重标（见 `EvalDatasetStore`）。
    let evalDatasets: EvalDatasetStore
    /// TD-8：把索引真正建起来的那条接线。**不是 Developer Tools 专属** ——
    /// 生产搜索（Week 5）要用的是同一个实例。
    let indexing: IndexingService
    /// 配置注册表 + 上线阈值 + 最近一次跑批（backlog 5.1–5.4）。
    /// 生产配置从它来 —— 否则 Promote 就只是改了一行 JSON。
    let release: ReleaseStore
    private let settings: SettingsStore?

    init(provider: (any EmbeddingProvider)?,
         vectors: InMemoryVectorStore,
         recorder: RetrievalTraceRecorder,
         derived: DerivedDataStore,
         indexing: IndexingService,
         release: ReleaseStore? = nil,
         evalDatasets: EvalDatasetStore? = nil,
         settings: SettingsStore? = nil,
         route: EmbeddingRoute = .unavailable("尚未选择 embedding 路线")) {
        self.provider = provider
        self.route = route
        self.vectors = vectors
        self.recorder = recorder
        self.derived = derived
        self.indexing = indexing
        self.release = release ?? ReleaseStore()
        self.evalDatasets = evalDatasets ?? EvalDatasetStore()
        self.settings = settings
    }

    var indexedCount: Int { indexing.indexedChunks }

    /// 库里有没有中文 —— **缓存值**。全库扫描实测 200 篇约 26ms 且在 main actor 上，
    /// 放进编辑路径会随库线性变成打字卡顿。只在低频时机（启动 / 手动 Rescan /
    /// 设置变更）重算，编辑时只看被改的那一篇（见 `noteDidChange`）。
    private(set) var corpusHasHan = false
    /// 库里有没有拉丁字母。与 `corpusHasHan` 一起决定「这是不是双语库」——
    /// 只有双语库才存在「本地一次只覆盖一种语言」的问题（P1 #8）。
    private(set) var corpusHasLatin = false

    /// P1 #8 · 零结果时该不该提「开启云端能搜到另一种语言」。
    ///
    /// 判断全在内核（`EmbeddingRouter.shouldOfferCloudUpgrade`），这里只把四个输入凑齐。
    /// **不在 View 里重写条件** —— 两处条件迟早会漂移。
    var offersCloudUpgrade: Bool {
        EmbeddingRouter.shouldOfferCloudUpgrade(
            route: route,
            cloudConfigured: settings?.isCloudEmbeddingConfigured ?? false,
            cloudConsentGranted: settings?.hasAcceptedCloudEmbeddingNotice ?? false,
            corpusContainsHan: corpusHasHan,
            corpusContainsLatin: corpusHasLatin)
    }

    /// 按当前语料 + 设置**应该**走的路线。与 `route`（当前生效的）不同时，
    /// 说明需要一次重建索引才能切过去。
    ///
    /// **不自动切。** 换向量空间 = 清空索引 + 全库重嵌，而且可能是付费云端调用；
    /// 在用户打字打到一半时替他做这个决定是不合适的。UI 据此给一个显式入口。
    private(set) var desiredRoute: EmbeddingRoute?

    /// 有待用户确认的路线变更。
    var hasPendingRouteChange: Bool { desiredRoute != nil }

    /// 启动：先按库里有没有中文选定 provider，再灌回落盘向量、补齐缺的。
    func startIndexing() async {
        // 启动不是热路径，这里做一次全库扫描是合理的。
        await resolveProvider(rescanCorpus: true, rebuildIfChanged: false)
        await indexing.start()
    }

    /// 重选路线并应用。
    ///
    /// - Parameter rescanCorpus: 是否重扫全库判定「有没有中文」。**只在低频时机传 true。**
    /// - Parameter rebuildIfChanged: 换了向量空间是否立刻重建索引。
    func resolveProvider(rescanCorpus: Bool = true, rebuildIfChanged: Bool = true) async {
        if rescanCorpus {
            let cards = indexing.fetchCards()
            corpusHasHan = ProductionEmbedding.corpusContainsHan(cards: cards, derived: derived)
            // 双语判断只服务 P1 #8 的提示，不参与路由 —— 一次扫描顺带取到，不额外遍历。
            corpusHasLatin = ProductionEmbedding.corpusContainsLatin(cards: cards, derived: derived)
        }
        let decision = currentDecision()
        route = decision.route
        provider = decision.provider
        desiredRoute = nil
        let reason: String?
        if case .unavailable(let message) = decision.route { reason = message } else { reason = nil }
        if rebuildIfChanged {
            await indexing.applyProvider(decision.provider, unavailableReason: reason)
        } else {
            indexing.adoptProvider(decision.provider, unavailableReason: reason)
        }
    }

    private func currentDecision() -> ProductionEmbedding.Decision {
        ProductionEmbedding.decide(
            corpusContainsHan: corpusHasHan,
            cloudConfigured: settings?.isCloudEmbeddingConfigured ?? false,
            cloudConsentGranted: settings?.hasAcceptedCloudEmbeddingNotice ?? false,
            makeCloud: { settings?.makeCloudEmbeddingProvider() ?? .failure(.unavailable("未配置")) }
        )
    }

    /// 一次编辑之后。**这是热路径，必须便宜。**
    ///
    /// 索引照常走 `IndexingService` 自己的合并 + 600ms 防抖；
    /// 路线这边只做一次**单篇**汉字判定，而且**只升不降**：
    ///
    /// - 这一篇出现了汉字而缓存还是 false → 缓存升为 true，标记「路线需要变更」，
    ///   **但不重建**（等用户确认）。
    /// - 这一篇没有汉字 → 什么都不做。判断「是不是最后一篇中文笔记被清空了」需要
    ///   全库扫描，而降级不紧急（英文库用着云端只是浪费，不是错），
    ///   留给下次启动或手动 Rescan。这样也避免了打字时路线来回翻。
    func noteDidChange(_ noteID: String) {
        indexing.noteDidChange(noteID)
        guard !corpusHasHan else { return }
        guard let card = indexing.card(withID: noteID),
              ProductionEmbedding.noteContainsHan(card, derived: derived) else { return }
        corpusHasHan = true
        refreshDesiredRoute()
    }

    func noteWasDeleted(_ noteID: String) async {
        await indexing.noteWasDeleted(noteID)
        // 删笔记同样不重扫全库：这里不会**新增**中文，只可能减少，而降级不紧急。
        refreshDesiredRoute()
    }

    /// 一批笔记被删除 —— 删文件夹走这条。
    ///
    /// 文件夹删除此前**完全没有**接线：SwiftData 的 cascade 删掉了笔记，
    /// 而 derived 数据在另一个 container 里，没有任何 cascade 能到达它。
    /// 残留的向量会继续进 topK，搜索页拿 noteID 回查笔记失败后静默丢掉那一行 ——
    /// 用户看到的不是错误结果，而是**少了一条结果**。
    func notesWereDeleted(_ noteIDs: [String]) async {
        await indexing.notesWereDeleted(noteIDs)
        refreshDesiredRoute()
    }

    /// derived 数据与笔记库的对账。只查不改。
    func derivedConsistency() async -> DerivedConsistencyReport {
        await indexing.consistencyReport()
    }

    /// 设置变了（填了 Key、给了同意）→ 重新看一眼应该走哪条，但不擅自重建。
    func refreshDesiredRoute() {
        let decision = currentDecision()
        desiredRoute = decision.route == route ? nil : decision.route
    }

    /// 用户确认切换路线（Developer Mode 的 Rescan / 搜索状态条的入口）。
    func applyDesiredRoute() async {
        await resolveProvider(rescanCorpus: true, rebuildIfChanged: true)
    }

    /// 同意云端上传。**唯一把同意写进设置的地方**，写完立刻切换路线。
    func grantCloudEmbeddingConsent() async {
        settings?.hasAcceptedCloudEmbeddingNotice = true
        await applyDesiredRoute()
    }
}
