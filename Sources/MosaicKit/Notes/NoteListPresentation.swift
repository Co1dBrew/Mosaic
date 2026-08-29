import Foundation

/// # 首页笔记流的**取值规则**（`UI_REDESIGN.md` v2 §2.3）
///
/// 一行只有三组信息：`[📌] 标题 · 相对时间` / `AI 一句话` / `[●]`。
/// 这里管的是中间那一行的三级回退，以及文件夹 chip 行的构成。
///
/// ## 为什么这些在内核里
///
/// 它们都是**纯取值**，没有 SwiftUI、没有 SwiftData。放在 View 里就只能靠截图
/// 走查来验证「没有摘要时显示什么」，而这恰恰是最容易漏的一档 ——
/// 新建的笔记在生成总结之前一直处于那一档。
public enum NoteListPresentation {

    /// 笔记行第二行。**三级回退**：
    ///
    /// 1. `summary.baseOneLiner`
    /// 2. 第一个文字块的**纯文本**首行（走 `MarkdownText.plainText`，
    ///    否则 `#` / `*` / `---` 会泄漏到列表里）
    /// 3. 内容类型描述（「1 段录音」）
    ///
    /// 全空时返回 `nil` —— 由调用方决定是留空还是显示占位，而不是在这里编一句话。
    public static func secondaryLine(oneLiner: String?,
                                     blocks: [CardBlockContent],
                                     limit: Int = 80) -> String? {
        if let oneLiner {
            let trimmed = oneLiner.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return truncate(trimmed, to: limit) }
        }
        if let excerpt = firstTextExcerpt(blocks, limit: limit) { return excerpt }
        return contentTypeDescription(blocks)
    }

    /// 第一个非空文字块的首行纯文本。
    public static func firstTextExcerpt(_ blocks: [CardBlockContent], limit: Int = 80) -> String? {
        for block in blocks.sorted(by: { $0.order < $1.order }) where block.kind == .text {
            let plain = MarkdownText.plainText(from: block.text ?? "")
            // 首行而不是全文：列表行最多两行，从第二段开始的内容永远看不到，
            // 但会把截断位置推到一个奇怪的地方。
            guard let line = plain.split(separator: "\n", omittingEmptySubsequences: true).first else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            return truncate(trimmed, to: limit)
        }
        return nil
    }

    /// 「1 段录音」「2 张图片 · 1 个文档」。
    ///
    /// 按 `BlockKind.allCases` 的固定顺序输出，不按块在文档里的顺序 ——
    /// 同一批内容换个排序就换一种描述，会让人以为笔记变了。
    public static func contentTypeDescription(_ blocks: [CardBlockContent]) -> String? {
        var counts: [BlockKind: Int] = [:]
        for block in blocks where !isEmpty(block) {
            counts[block.kind, default: 0] += 1
        }
        let parts = BlockKind.allCases.compactMap { kind -> String? in
            guard let n = counts[kind], n > 0 else { return nil }
            return "\(n) \(unit(kind))"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 空笔记：既没有文字，也没有任何媒体。
    public static func isEmptyNote(_ blocks: [CardBlockContent]) -> Bool {
        blocks.allSatisfy(isEmpty)
    }

    private static func unit(_ kind: BlockKind) -> String {
        switch kind {
        case .text:  return "段文字"
        case .image: return "张图片"
        case .audio: return "段录音"
        case .file:  return "个文档"
        case .link:  return "个链接"
        }
    }

    private static func isEmpty(_ block: CardBlockContent) -> Bool {
        switch block.kind {
        case .text:  return MarkdownText.plainText(from: block.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image: return (block.imageAssetRef ?? "").isEmpty
        case .audio: return (block.audioAssetRef ?? "").isEmpty
        case .file:  return (block.fileName ?? "").isEmpty
        case .link:  return (block.url ?? "").isEmpty
        }
    }

    private static func truncate(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
}

// MARK: - 文件夹 chip 行（§2.2）

/// 首页当前在看哪一组笔记。**「未归类」用 `folder == nil` 表达**，
/// 不建实体文件夹行 —— 它因此天然不可重命名、不可删除，正是一个系统桶该有的性质。
public enum NoteFilter: Sendable, Equatable, Hashable {
    case all
    case unfiled
    case folder(id: String)
}

public struct FolderChip: Sendable, Equatable, Identifiable {
    public enum Role: Sendable, Equatable {
        case all
        case unfiled
        case folder
        /// 末尾的 `⋯`，进文件夹管理页。
        case manage
    }
    public let id: String
    public let title: String
    /// 用户文件夹才有；`all` / `unfiled` / `manage` 为 nil。
    public let colorHex: String?
    public let iconName: String?
    public let role: Role
    public let filter: NoteFilter?

    public init(id: String, title: String, colorHex: String? = nil,
                iconName: String? = nil, role: Role, filter: NoteFilter?) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.iconName = iconName
        self.role = role
        self.filter = filter
    }
}

public struct FolderChipSource: Sendable, Equatable {
    public let id: String
    public let name: String
    public let colorHex: String
    public let iconName: String
    public init(id: String, name: String, colorHex: String, iconName: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
    }
}

public enum FolderChipBar {

    /// 整行是否隐藏。
    ///
    /// **用户文件夹数为 0 时隐藏** —— 新用户第一眼该看到干净的笔记流，
    /// 不是一个空的分类系统（§2.2）。注意判据是「有没有用户文件夹」，
    /// 不是「有没有笔记」：一条未归类的笔记不构成分类。
    public static func isHidden(folderCount: Int) -> Bool { folderCount == 0 }

    /// 构成：`全部` → `未归类`（仅当存在未归类笔记）→ 用户文件夹（按 sortOrder）→ `⋯`
    ///
    /// - Parameter hasUnfiledNotes: 库里有没有 `folder == nil` 的笔记。
    ///   没有就不显示「未归类」——一个永远空的筛选项只会占宽度。
    public static func chips(folders: [FolderChipSource],
                             hasUnfiledNotes: Bool) -> [FolderChip] {
        guard !isHidden(folderCount: folders.count) else { return [] }
        var chips: [FolderChip] = [
            FolderChip(id: "all", title: "全部", role: .all, filter: .all)
        ]
        if hasUnfiledNotes {
            chips.append(FolderChip(id: "unfiled", title: "未归类", role: .unfiled, filter: .unfiled))
        }
        chips += folders.map {
            FolderChip(id: $0.id, title: $0.name, colorHex: $0.colorHex,
                       iconName: $0.iconName, role: .folder, filter: .folder(id: $0.id))
        }
        chips.append(FolderChip(id: "manage", title: "⋯", role: .manage, filter: nil))
        return chips
    }

    /// 点击一个 chip 之后的新筛选。
    ///
    /// **再次点击已选中的 chip → 回到「全部」**（§2.2）。
    /// `⋯` 不改筛选，它是一次导航。
    public static func toggled(current: NoteFilter, tapped: FolderChip) -> NoteFilter? {
        guard let filter = tapped.filter else { return nil }
        return current == filter ? .all : filter
    }

    /// 导航栏标题 = 当前筛选。用户永远知道自己在看哪个集合（§2.2）。
    public static func title(for filter: NoteFilter, folders: [FolderChipSource]) -> String {
        switch filter {
        case .all:     return "全部笔记"
        case .unfiled: return "未归类"
        case .folder(let id):
            // 文件夹刚被删掉时退回「全部笔记」，而不是显示一个空标题。
            return folders.first { $0.id == id }?.name ?? "全部笔记"
        }
    }
}
