import Foundation
import Observation
import MosaicKit

// MARK: - 仅内部构建
//
// Developer Tools **整目录**只在 DEBUG 或显式打开 `INTERNAL_BUILD` 的构建里编译。
// 正式 Release 里这些类型根本不存在 —— 不是「入口藏起来」，是**没有这段代码**，
// 所以不可能有第二条路径把它们暴露给普通用户（`design/DEVTOOLS.md` §1.2）。
//
// 内部 TestFlight 需要它时：在 Release 配置的
// `SWIFT_ACTIVE_COMPILATION_CONDITIONS` 里加 `INTERNAL_BUILD`。
#if DEBUG || INTERNAL_BUILD

/// # D7 / D8 —— Release Gate 的 ViewModel（backlog 5.3 / 5.4）
///
/// **它不算判定。** 判定在 `ReleaseGate.evaluate` 里，一行 `allSatisfy`
/// （`DECISION_LOG.md` D-UI-DEV-008）。这个类只做三件事：
/// 把 store 里的东西摆出来、把 Promote 的结果告诉界面、把「为什么不能上」翻译成一句话。
///
/// 之所以要一个 ViewModel 而不是让 View 直接读 store：Promote 之后要顺带
/// **让索引服务改用新配置**（否则 Promote 就只是改了一行 JSON），
/// 而那是一次副作用，不该写在 `body` 里。
@Observable
@MainActor
final class ReleaseGateViewModel {

    private let store: ReleaseStore
    /// 生产索引服务。Promote 换掉 chunk 策略时，索引必须跟着重建 ——
    /// 老索引的 chunkID 是按旧策略算的，vector 命中会被静默丢弃。
    private let indexing: IndexingService?

    /// Promote 之后的一句反馈。成功也要说 —— 一个什么都不说的上线动作
    /// 会让人不确定它到底做了没有。
    private(set) var banner: String?

    init(store: ReleaseStore, indexing: IndexingService? = nil) {
        self.store = store
        self.indexing = indexing
    }

    // MARK: 输出

    var decision: GateDecision { store.decision }
    var checks: [GateCheck] { decision.checks }
    var target: RetrievalConfigRecord { store.evaluationTarget }
    var productionRecord: RetrievalConfigRecord { store.registry.production }
    var thresholds: GateThresholds { store.thresholds }
    var hasCandidate: Bool { store.registry.candidate != nil }
    var currentRun: EvalRun? { store.latestRun }
    var baselineRun: EvalRun? { store.latestBaselineRun }

    /// `Promote to Production` 是否可点。
    ///
    /// 三个条件缺一不可：判定 PASS · 有候选 · 候选不是当前生产。
    /// 界面上置灰只是**呈现**；真正的拦截在 `RetrievalConfigRegistry.promote`，
    /// 它不接受非 PASS 的判定。两层都要有 —— 只有 UI 层的拦截，
    /// 第二个调用点出现的那天就绕过去了。
    var canPromote: Bool {
        decision.isPass && hasCandidate && target.role == .candidate
    }

    /// 判定区下面那句话。**先回答「能不能上」，再回答「为什么不能」。**
    var verdictDetail: String {
        switch decision.status {
        case .pass:
            return hasCandidate
                ? "四项检查全部通过，可以把 \(target.config.version) 推到生产。"
                : "四项检查全部通过。当前没有候选配置 —— 去 Retrieval Config 派生一份并设为 candidate。"
        case .blocked:
            return decision.blockingReasons.joined(separator: "；")
        case .stale:
            return decision.staleReason ?? "评测结果与当前配置不一致，重跑评测。"
        }
    }

    // MARK: 动作

    func promote() {
        guard canPromote else { return }
        let version = target.config.version
        guard store.promote(id: target.id, decision: decision) else {
            banner = store.lastError ?? "Promote 失败。"
            return
        }
        banner = "\(version) 已上线。"
        // 换了 chunk 策略 / embedding 版本就必须重建索引 —— 两套策略的记录混在一个
        // store 里，chunkID 对不上，vector 命中会被静默丢弃（§15.3）。
        if let indexing {
            let newConfig = store.productionConfig
            Task { @MainActor in
                await indexing.applyConfig(newConfig)
            }
        }
    }

    func dismissBanner() { banner = nil }
}

#endif  // DEBUG || INTERNAL_BUILD
