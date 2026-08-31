import Foundation
import Observation
import MosaicKit

/// # 配置注册表与上线阈值的持久化（backlog 5.1 / 5.2）
///
/// ## 为什么和 `EvalDatasetStore` 一样是文件而不是 derived store
///
/// 同一条理由：derived store 的契约是「可以随时清空，因为都能重建」。
/// **「哪一套配置在线上跑」不能重建** —— 清掉之后线上跑的是什么就无从查起了。
///
/// ## 跑批结果为什么只在内存里
///
/// `EvalRun` 带着 `EvalFailure`（不可 Codable，也不该 Codable —— 它引用的是
/// 本机笔记 id 与当次语料）。重启后没有跑批结果，Gate 会如实显示 `STALE`
/// 并要求重跑 —— 这正是想要的行为：**隔了一次重启的评测结果不该拿来放行上线。**
@Observable
@MainActor
final class ReleaseStore {

    private(set) var registry: RetrievalConfigRegistry
    private(set) var thresholds: GateThresholds
    /// 最近一次 current / baseline 跑批。由 `RetrievalEvalViewModel` 写入 ——
    /// Gate 不自己跑评测，否则会出现两处各自跑出来的数字。
    private(set) var latestRun: EvalRun?
    private(set) var latestBaselineRun: EvalRun?
    /// **跑批当时**的测量环境。分层 policy 之后它是判定的前置条件 ——
    /// 在记录时捕获，而不是判定时补一个，否则记的就不是那批数字的环境了。
    private(set) var latestRunEnvironment: RunEnvironment?
    private(set) var lastError: String?

    private let fileURL: URL
    /// 落盘目录。测试要能重开一个实例读同一份文件。
    let storageDirectory: URL

    init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.storageDirectory = dir
        self.fileURL = dir.appendingPathComponent("release-config.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let loaded = Self.load(from: fileURL)
        var registry = loaded?.registry ?? RetrievalConfigRegistry()
        // 落盘的注册表可能比这个 App 版本还老。产品决策换了生产配置
        // （hybrid → keyword）之后，老设备上那条根记录仍然是 hybrid，
        // 而生产搜索读的正是它 —— 于是真机上跑的和代码/文档说的不是一回事。
        // 只迁移根记录；经 Gate Promote 上线过的配置不动（见 `migrateRootProduction`）。
        let migrated = registry.migrateRootProduction(to: .production)
        self.registry = registry
        self.thresholds = loaded?.thresholds ?? .default
        if migrated { save() }
    }

    private struct Persisted: Codable {
        var registry: RetrievalConfigRegistry
        var thresholds: GateThresholds
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MosaicEval", isDirectory: true)
    }

    private static func load(from url: URL) -> Persisted? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Persisted.self, from: data)
    }

    // MARK: 读

    /// 生产检索配置。索引服务与生产搜索都读它 —— 否则 Promote 就只是改了一行 JSON。
    var productionConfig: RetrievalConfig { registry.productionConfig }

    /// 当前要判定的那一套。有候选就判候选，没有就判生产
    /// （「现在这套还满足阈值吗」同样是个有意义的问题）。
    var evaluationTarget: RetrievalConfigRecord { registry.candidate ?? registry.production }

    var decision: GateDecision {
        ReleaseGate.evaluate(configVersion: evaluationTarget.config.version,
                             current: latestRun,
                             baseline: latestBaselineRun,
                             thresholds: thresholds,
                             environment: latestRunEnvironment)
    }

    // MARK: 写

    func recordRun(_ run: EvalRun, environment: RunEnvironment? = nil) {
        latestRun = run
        // 默认捕获**当下**的环境。模拟器 / debug 构建会因此被 perf-v2 判 STALE ——
        // 那正是想要的：不能拿模拟器的数字 Promote。
        latestRunEnvironment = environment ?? RunEnvironment.capture(layer: .firstResult)
        // 换了 current 就没有可比的 baseline 了（§14.3 同一条理由）。
        latestBaselineRun = nil
    }

    func recordBaselineRun(_ run: EvalRun) { latestBaselineRun = run }

    @discardableResult
    func duplicate(from id: String, mutate: (inout RetrievalConfig) -> Void) -> RetrievalConfigRecord? {
        do {
            let record = try registry.duplicate(from: id, mutate: mutate)
            save()
            return record
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    func setCandidate(id: String) {
        do { try registry.setCandidate(id: id); save(); lastError = nil }
        catch { lastError = String(describing: error) }
    }

    func remove(id: String) {
        do { try registry.remove(id: id); save(); lastError = nil }
        catch { lastError = String(describing: error) }
    }

    /// 上线。判定由内核校验（PASS + 同一套配置），这里只负责落盘与告知失败原因。
    @discardableResult
    func promote(id: String, decision: GateDecision) -> Bool {
        do {
            _ = try registry.promote(id: id, decision: decision)
            save()
            lastError = nil
            return true
        } catch {
            lastError = String(describing: error)
            return false
        }
    }

    func updateThresholds(_ new: GateThresholds) {
        thresholds = new
        save()
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Persisted(registry: registry, thresholds: thresholds))
                .write(to: fileURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
