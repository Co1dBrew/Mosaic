import Foundation

/// # 一条被记录下来的检索配置（backlog 5.1）
///
/// `RetrievalConfig` 是**参数**，这里是**身份**：谁派生自谁、什么时候建的、
/// 是不是当前生产、什么时候被 promote 的。
///
/// 两者分开的理由是 `RetrievalConfig` 会被 Trace / EvalRun 大量复制传递，
/// 给它挂上 `promotedAt` 之后，每一条 trace 里都会带一份「上线时间」——
/// 而那不是一次检索的属性。
public struct RetrievalConfigRecord: Sendable, Equatable, Codable, Identifiable {

    /// **三个角色，不是标签集合。** 一条记录同一时刻只能是其中之一 ——
    /// 「既是生产又是候选」会让 Promote 的前后状态无法表达。
    public enum Role: String, Sendable, Equatable, Codable {
        /// 线上正在用的那一套。**全局有且只有一条。**
        case production
        /// 正在被评测、准备 promote 的那一套。**至多一条** ——
        /// 两个候选同时存在时，Release Gate 的「能不能上」就没有主语了。
        case candidate
        /// 派生出来但还没被指定为候选。
        case draft
    }

    public let id: String
    public let config: RetrievalConfig
    public let createdAt: Date
    /// 派生自哪一条。根记录为 nil —— 它不是从任何东西派生的，是初始生产配置。
    public let derivedFrom: String?
    public internal(set) var role: Role
    /// 只有 promote 会写。**非 nil 即代表这条配置曾经上过线**，
    /// 即使后来被别的版本取代（历史不抹掉，否则回溯一次线上问题就无从查起）。
    public internal(set) var promotedAt: Date?

    public init(id: String = UUID().uuidString,
                config: RetrievalConfig,
                createdAt: Date = Date(),
                derivedFrom: String? = nil,
                role: Role = .draft,
                promotedAt: Date? = nil) {
        self.id = id
        self.config = config
        self.createdAt = createdAt
        self.derivedFrom = derivedFrom
        self.role = role
        self.promotedAt = promotedAt
    }

    public var version: String { config.version }
}

/// # 配置注册表（backlog 5.1）
///
/// ## 唯一的核心规定：生产配置只能经 Promote 更换
///
/// 这不是靠「UI 上不要放编辑按钮」实现的，而是**没有 API 能改生产记录的参数**：
/// `duplicate` 只能派生出 draft，`promote` 只接受一个 **PASS 的 `GateDecision`**。
/// 把它做成纪律的版本迟早会在某次赶工里被绕过 —— 而绕过它的代价是线上跑着一套
/// 没人评测过的检索配置，且没有任何记录说明它是什么时候换的。
///
/// ## 为什么是值类型
///
/// App 侧要把它整个 JSON 落盘（与 `EvalDatasetStore` 同一个理由：
/// 它是人工决策的产物，不可重建，所以不进 derived store）。
public struct RetrievalConfigRegistry: Sendable, Equatable, Codable {

    public enum ConfigError: Error, Equatable, CustomStringConvertible {
        case unknownRecord(String)
        case cannotEditProduction
        case notPromotable(String)
        case blockedByGate([String])
        case decisionIsForAnotherConfig(decision: String, record: String)

        public var description: String {
            switch self {
            case let .unknownRecord(id):
                return "没有这条配置记录：\(id)"
            case .cannotEditProduction:
                return "生产配置不可直接编辑 —— 派生一份新版本，评测通过后 Promote。"
            case let .notPromotable(id):
                return "只有 candidate 才能 promote（\(id)）。"
            case let .blockedByGate(reasons):
                return "Release Gate 未通过，不能 promote：" + reasons.joined(separator: "；")
            case let .decisionIsForAnotherConfig(decision, record):
                return "这次判定跑的是 \(decision)，与要 promote 的 \(record) 不是同一套配置 —— 重新跑评测。"
            }
        }
    }

    public private(set) var records: [RetrievalConfigRecord]
    /// 版本号自增序列。**不用 `records.count`** —— 删掉一条 draft 之后
    /// 下一个版本号就会撞上一个已经存在过的版本，而 EvalRun / Trace 里记的正是这个字符串。
    private var sequence: Int

    /// 初始注册表：当前的 `RetrievalConfig.production` 作为根生产记录。
    /// 它没有 `promotedAt` —— 它不是被 promote 上去的，是初始值。
    public init(production: RetrievalConfig = .production, createdAt: Date = Date()) {
        self.records = [RetrievalConfigRecord(config: production,
                                              createdAt: createdAt,
                                              role: .production)]
        self.sequence = 1
    }

    // MARK: 读

    /// 生产记录。构造函数保证它存在，`promote` 保证它唯一。
    public var production: RetrievalConfigRecord {
        records.first { $0.role == .production }
            ?? records[0]   // 结构上不可达；宁可返回第一条也不 crash 在检索路径上
    }

    public var productionConfig: RetrievalConfig { production.config }

    public var candidate: RetrievalConfigRecord? { records.first { $0.role == .candidate } }

    public func record(id: String) -> RetrievalConfigRecord? { records.first { $0.id == id } }

    /// 曾经上过线的版本，按 promote 时间倒序。回溯线上问题时的第一手材料。
    public var promotionHistory: [RetrievalConfigRecord] {
        records.filter { $0.promotedAt != nil }.sorted { ($0.promotedAt ?? .distantPast) > ($1.promotedAt ?? .distantPast) }
    }

    // MARK: 写

    /// 从某条记录派生一份新版本（`DEVTOOLS.md` §4.6 的 `Duplicate as new version`）。
    ///
    /// 新记录一律是 `draft`：派生本身不表达「我要上这个」。
    /// `version` 由注册表分配，不接受手填 —— 手填的版本号会和实际参数对不上，
    /// 而 Trace / EvalRun 里记的就是这个字符串。
    @discardableResult
    public mutating func duplicate(from id: String,
                                   createdAt: Date = Date(),
                                   mutate: (inout RetrievalConfig) -> Void = { _ in }) throws -> RetrievalConfigRecord {
        guard let parent = record(id: id) else { throw ConfigError.unknownRecord(id) }
        sequence += 1
        var config = parent.config
        mutate(&config)
        config.version = "retrieval-v\(sequence)"
        let new = RetrievalConfigRecord(config: config, createdAt: createdAt,
                                        derivedFrom: parent.id, role: .draft)
        records.append(new)
        return new
    }

    /// 指定候选。**至多一条**：把旧候选降回 draft，不是并存。
    public mutating func setCandidate(id: String) throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw ConfigError.unknownRecord(id) }
        guard records[index].role != .production else { throw ConfigError.cannotEditProduction }
        for i in records.indices where records[i].role == .candidate { records[i].role = .draft }
        records[index].role = .candidate
    }

    /// 上线。**这是生产配置唯一的更换入口。**
    ///
    /// - Parameter decision: 必须是**这套配置**的 PASS 判定。
    ///   接受任意 decision 等于把「全 PASS 才能 promote」交给调用方自觉；
    ///   而校验 `configVersion` 是为了拦住「改完参数没重跑评测就上线」——
    ///   那种情况下判定还是绿的，但它判的是上一套配置。
    @discardableResult
    public mutating func promote(id: String,
                                 decision: GateDecision,
                                 at date: Date = Date()) throws -> RetrievalConfigRecord {
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw ConfigError.unknownRecord(id) }
        guard records[index].role == .candidate else { throw ConfigError.notPromotable(id) }
        guard decision.configVersion == records[index].config.version else {
            throw ConfigError.decisionIsForAnotherConfig(decision: decision.configVersion,
                                                         record: records[index].config.version)
        }
        guard decision.isPass else { throw ConfigError.blockedByGate(decision.blockingReasons) }

        for i in records.indices where records[i].role == .production { records[i].role = .draft }
        records[index].role = .production
        records[index].promotedAt = date
        return records[index]
    }

    // MARK: 迁移

    /// # 把「从未被 Promote 过的」生产记录迁移到当前编译期默认
    ///
    /// 这条存在的理由是一个具体的失败：产品决策把生产从 hybrid 改成 keyword、
    /// `RetrievalConfig.production` 也改了，但**老设备上已经落盘的注册表里
    /// 那条根记录还是 hybrid**。`ReleaseStore` 优先读文件，于是这台手机上
    /// 线上跑的仍然是 hybrid —— 代码、文档、Gate 全都说 keyword，只有真机在说另一件事。
    /// 这正是「文档说 Keyword，代码默认 Hybrid」那类不一致的持久化版本。
    ///
    /// **只迁移根记录**（`promotedAt == nil`）。经过 Gate Promote 上线的配置
    /// 是一次有记录的人为决定，不能被一次 App 更新悄悄改掉；它需要的是
    /// 再走一次 Promote。
    ///
    /// - Returns: 真的换掉了返回 `true`。调用方据此决定要不要落盘。
    @discardableResult
    public mutating func migrateRootProduction(to target: RetrievalConfig,
                                               createdAt: Date = Date()) -> Bool {
        guard let index = records.firstIndex(where: { $0.role == .production }) else { return false }
        guard records[index].promotedAt == nil else { return false }
        guard records[index].config != target else { return false }
        let old = records[index]
        records[index] = RetrievalConfigRecord(id: old.id,
                                               config: target,
                                               createdAt: createdAt,
                                               derivedFrom: old.derivedFrom,
                                               role: .production,
                                               promotedAt: nil)
        return true
    }

    /// 删一条 draft。生产与候选不能删 —— 删掉当前生产配置之后，线上跑的是什么就没有记录了。
    public mutating func remove(id: String) throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw ConfigError.unknownRecord(id) }
        guard records[index].role == .draft else { throw ConfigError.cannotEditProduction }
        records.remove(at: index)
    }
}
