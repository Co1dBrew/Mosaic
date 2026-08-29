import Foundation

/// # Derived 数据一致性对账
///
/// ## 它防的是哪一条失败链
///
/// ```
/// 删除文件夹
///   ↓ SwiftData cascade 删掉其中的笔记
///   ↓ 但 derived store 在另一个 container 里，**没有任何 cascade 能到达它**
///   ↓ 残留的 embedding 仍然参与检索
///   ↓ 它进了 topK
///   ↓ 用 noteID 回查笔记 → 查不到
///   ↓ 搜索页把这一行**静默丢掉**
/// ```
///
/// 最后一步是最坏的：用户看到的不是一条错误的结果，而是**少了一条结果**，
/// 而且没有任何迹象说明发生过什么。第 5 名被一条不存在的笔记占了位，
/// 真正第 6 名的笔记永远出不来。
///
/// ## 为什么对账逻辑在内核而不在 App
///
/// 判断「哪些是孤儿」是纯集合运算，它不需要 SwiftData，也就不需要模拟器才能测。
/// App 那一层只负责**取三个集合**（活着的笔记 / derived 里的 / 内存索引里的），
/// 取完交给这里。这样「孤儿的定义」只有一处，而它是可断言的。
///
/// ## 三个来源都要查，不能只查一个
///
/// derived store 的 embedding、derived store 的 OCR、内存向量索引，三者可以各自
/// 走偏：删除路径漏掉任意一个都会留下不同形态的孤儿。只查 embedding 会漏掉
/// 「OCR 还在、下次重新索引时被当成有效 overlay」这一种。
public struct DerivedConsistencyReport: Sendable, Equatable, Codable {

    /// 笔记库里当前存在的笔记数。分母，用来判断报告本身是否可信 ——
    /// 笔记库读不到时（0 篇）不能把整个 derived store 判成孤儿。
    public let liveNoteCount: Int
    /// derived store 里 embedding 引用了、但笔记已经不存在的 noteID。
    public let orphanEmbeddingNoteIDs: [String]
    /// derived store 里 OCR 引用了、但笔记已经不存在的 noteID。
    public let orphanOCRNoteIDs: [String]
    /// 内存向量索引里引用了、但笔记已经不存在的 noteID。
    public let orphanIndexedNoteIDs: [String]

    public init(liveNoteCount: Int,
                orphanEmbeddingNoteIDs: [String],
                orphanOCRNoteIDs: [String],
                orphanIndexedNoteIDs: [String]) {
        self.liveNoteCount = liveNoteCount
        self.orphanEmbeddingNoteIDs = orphanEmbeddingNoteIDs.sorted()
        self.orphanOCRNoteIDs = orphanOCRNoteIDs.sorted()
        self.orphanIndexedNoteIDs = orphanIndexedNoteIDs.sorted()
    }

    /// 三处孤儿的并集。清理动作按笔记走，所以并集才是要处理的那份清单。
    public var orphanNoteIDs: [String] {
        Set(orphanEmbeddingNoteIDs).union(orphanOCRNoteIDs).union(orphanIndexedNoteIDs).sorted()
    }

    /// **唯一的通过条件：一条孤儿都没有。**
    ///
    /// 不设「容忍 N 条」的阈值：孤儿不是统计量，是一条具体的错误结果。
    /// 允许 3 条等于允许搜索结果里有 3 个洞。
    public var isConsistent: Bool { orphanNoteIDs.isEmpty }

    /// 一行说明，Developer Tools 直接显示。
    public var summary: String {
        guard !isConsistent else { return "一致 · \(liveNoteCount) 篇笔记，无孤儿 derived 数据" }
        var parts: [String] = []
        if !orphanEmbeddingNoteIDs.isEmpty { parts.append("embedding \(orphanEmbeddingNoteIDs.count)") }
        if !orphanOCRNoteIDs.isEmpty { parts.append("OCR \(orphanOCRNoteIDs.count)") }
        if !orphanIndexedNoteIDs.isEmpty { parts.append("内存索引 \(orphanIndexedNoteIDs.count)") }
        return "发现孤儿：\(parts.joined(separator: " · "))，共 \(orphanNoteIDs.count) 篇笔记"
    }
}

public enum DerivedConsistency {

    /// 对账。
    ///
    /// - Parameter liveNoteIDs: 笔记库里当前存在的笔记 id。
    /// - Parameter embeddingNoteIDs: derived store 里出现过的 noteID（embedding 表）。
    /// - Parameter ocrNoteIDs: derived store 里出现过的 noteID（OCR 表）。
    /// - Parameter indexedNoteIDs: 内存向量索引里出现过的 noteID。
    ///
    /// - Note: **`liveNoteIDs` 为空时不下「全是孤儿」的结论。** 空笔记库与
    ///   「笔记库这次没读出来」在这一层是同一个输入，而两者的正确动作相反：
    ///   前者该清空，后者清空就是把用户的索引删了。所以空库时只报告、不认定，
    ///   由调用方决定；`reconcile` 那一侧对应地拒绝在空库上执行删除。
    public static func check(liveNoteIDs: Set<String>,
                             embeddingNoteIDs: Set<String>,
                             ocrNoteIDs: Set<String>,
                             indexedNoteIDs: Set<String>) -> DerivedConsistencyReport {
        DerivedConsistencyReport(
            liveNoteCount: liveNoteIDs.count,
            orphanEmbeddingNoteIDs: Array(embeddingNoteIDs.subtracting(liveNoteIDs)),
            orphanOCRNoteIDs: Array(ocrNoteIDs.subtracting(liveNoteIDs)),
            orphanIndexedNoteIDs: Array(indexedNoteIDs.subtracting(liveNoteIDs)))
    }

    /// 这一次对账的结果**可不可以拿来执行删除**。
    ///
    /// 唯一的否决条件是「活着的笔记数为 0，而 derived 里还有数据」：这种组合更可能
    /// 是一次读取失败而不是用户真的把所有笔记删光了，而两者的代价完全不对称 ——
    /// 猜错方向会把一份要几分钟才能重建（云端还要花钱）的索引删掉。
    /// 真的清空了全部笔记时，下一次「删除最后一篇笔记」的常规路径已经清理过了。
    public static func isSafeToReconcile(_ report: DerivedConsistencyReport) -> Bool {
        !(report.liveNoteCount == 0 && !report.orphanNoteIDs.isEmpty)
    }
}
