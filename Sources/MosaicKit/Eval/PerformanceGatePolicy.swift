import Foundation

/// 一次跑批测的是哪一层延迟。
///
/// 一次跑批只能测一层 —— 三层的预算完全不同，混在一个 `p95Ms` 里判定必然出错。
public enum MeasuredLatencyLayer: String, Sendable, Equatable, Codable, CaseIterable {
    /// Metric A：keyword / 本地快通道 → 用户多久看到**第一批**可交互结果。
    case firstResult
    /// Metric B-local：本地嵌入 + 余弦 + RRF。全本机，可跨设备比较。
    case semanticLocal
    /// Metric B-cloud：含一次网络往返。**地理相关**，必须带 region 才有意义。
    case semanticCloud
}

/// # 分层性能预算（可版本化）
///
/// 原来的 `p95BudgetMs` 是**一个**数字，它同时被拿去判 keyword 快通道和云端语义 ——
/// 而后者含一次跨洲网络往返。一个数字判两件量级差 10 倍的事，判出来的结论没有意义。
///
/// ## 三条设计主张
///
/// 1. **Metric A 阻断，Metric B-cloud 只记录。** Metric A 是对用户的承诺
///    （多久看到东西），失败必须拦。Metric B-cloud 在 progressive enhancement 下
///    已有 keyword 兜底，所以 `semanticCloudP95Ms = nil` 表示「记录但不判定」。
///    这个取舍**显式写在 policy 里**，而不是藏在代码分支里。
/// 2. **测量环境是判定前置条件，不是脚注。** debug 构建、模拟器、低电量、发热
///    ——任一条不满足就判 **STALE 而不是 FAIL**：那不是「性能不达标」，
///    是「这批数字没有资格参与判定」，补救动作是换台机器重测。
/// 3. **region 不匹配同样是 STALE。** 同一份 policy 在 US→China 和 US→US 下
///    不该给出同一个判决。
public struct PerformanceGatePolicy: Sendable, Equatable, Codable {

    public var version: String

    /// Metric A —— 第一批可交互结果。**阻断项。**
    public var firstResultP50Ms: Double
    public var firstResultP95Ms: Double
    /// Metric B-local —— 本地语义。**阻断项**（全本机，可控）。
    public var semanticLocalP95Ms: Double
    /// Metric B-cloud —— 含网络。`nil` = **记录但不判定**。
    public var semanticCloudP95Ms: Double?

    /// 判定所需的测量环境。
    public var requiredDeviceClass: RunEnvironment.DeviceClass
    public var requiredBuildConfiguration: String
    /// `nil` = 不限区域。非 nil 时 region 不符判 STALE。
    public var requiredProviderRegion: String?

    public init(version: String = "perf-v2",
                firstResultP50Ms: Double = 100,
                firstResultP95Ms: Double = 250,
                semanticLocalP95Ms: Double = 250,
                semanticCloudP95Ms: Double? = nil,
                requiredDeviceClass: RunEnvironment.DeviceClass = .physicalDevice,
                requiredBuildConfiguration: String = "release",
                requiredProviderRegion: String? = nil) {
        self.version = version
        self.firstResultP50Ms = firstResultP50Ms
        self.firstResultP95Ms = firstResultP95Ms
        self.semanticLocalP95Ms = semanticLocalP95Ms
        self.semanticCloudP95Ms = semanticCloudP95Ms
        self.requiredDeviceClass = requiredDeviceClass
        self.requiredBuildConfiguration = requiredBuildConfiguration
        self.requiredProviderRegion = requiredProviderRegion
    }

    /// `perf-v1` —— 原 PRD 的单一 SLO，保留以便对照。
    /// 它不区分层，也不检查测量环境，所以 Mac debug 的数字也能进 Gate。
    public static let v1 = PerformanceGatePolicy(version: "perf-v1",
                                                firstResultP50Ms: 100,
                                                firstResultP95Ms: 250,
                                                semanticLocalP95Ms: 250,
                                                semanticCloudP95Ms: 250,
                                                requiredDeviceClass: .mac,
                                                requiredBuildConfiguration: "release")

    public static let v2 = PerformanceGatePolicy()

    /// `perf-none` —— **只判质量，不判延迟**。
    ///
    /// 用在「同一份评测集上比较两套配置的检索质量」这一类跑批上。
    ///
    /// 为什么需要它：`perf-v2` 的环境闸门（release + 真机）是给**延迟结论**设的，
    /// 而质量结论不受构建配置影响 —— v4 那一轮真机与 Mac 的质量数字**逐位相同**，
    /// 差别只在延迟。用延迟的环境要求去卡质量比较，结果是每次质量跑批都判 STALE，
    /// 于是没有人再看它，而这正是「一个总是被跳过的 Gate 等于没有 Gate」。
    ///
    /// 延迟判定仍然只在真机 release 上发生（`MosaicBench`），两者不互相替代：
    /// **这个 policy 不能用来声称延迟达标**，它连延迟那一行都不出。
    public static let qualityOnly = PerformanceGatePolicy(
        version: "perf-none",
        semanticCloudP95Ms: nil,
        requiredDeviceClass: .mac,
        requiredBuildConfiguration: "any")

    /// 这套 policy 判不判延迟。`perf-none` 不判，Gate 因此不出延迟那一行 ——
    /// 出一行「记录但不判定」会让人以为延迟被看过了。
    public var judgesLatency: Bool { version != "perf-none" }

    /// 某一层的 P95 预算。`nil` = 记录但不判定。
    public func p95Budget(for layer: MeasuredLatencyLayer) -> Double? {
        switch layer {
        case .firstResult:   return firstResultP95Ms
        case .semanticLocal: return semanticLocalP95Ms
        case .semanticCloud: return semanticCloudP95Ms
        }
    }

    public func p50Budget(for layer: MeasuredLatencyLayer) -> Double? {
        layer == .firstResult ? firstResultP50Ms : nil
    }

    /// 这批数字有没有资格参与判定。返回非 nil = 不合格的原因。
    ///
    /// `perf-none` 不检查环境：它本来就不给延迟结论，环境对质量结论没有影响。
    public func disqualification(_ environment: RunEnvironment?) -> String? {
        if version == "perf-none" { return nil }
        guard let environment else {
            return "这批跑批没有记录测量环境 —— 不知道它跑在什么机器、什么构建上"
        }
        if let reason = environment.disqualification(
            requiredDeviceClass: requiredDeviceClass,
            requiredBuildConfiguration: requiredBuildConfiguration) { return reason }
        if let required = requiredProviderRegion,
           environment.providerRegion != required {
            return "这批数字跑在 \(environment.providerRegion ?? "未记录区域")，判定要求 \(required)"
        }
        return nil
    }
}
