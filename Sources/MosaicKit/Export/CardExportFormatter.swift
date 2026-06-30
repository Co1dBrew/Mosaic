import Foundation

/// Value snapshot of a card for export (PRD §10.2 export/share). Dates are passed
/// pre-formatted so the formatter stays pure and deterministic (no locale/timezone
/// dependence in tests).
public struct CardExportContent: Sendable {
    public var title: String
    public var folderName: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var tags: [String]
    public var blocks: [CardBlockContent]
    public var summary: ExportSummary?

    public init(title: String, folderName: String? = nil, createdAt: String? = nil,
                updatedAt: String? = nil, tags: [String] = [], blocks: [CardBlockContent] = [],
                summary: ExportSummary? = nil) {
        self.title = title
        self.folderName = folderName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.blocks = blocks
        self.summary = summary
    }
}

public struct ExportSummary: Sendable {
    public var title, oneLiner, type, summary: String
    public var topics, keyPoints: [String]
    public var provider, model, generatedAt: String
    public var updates: [ExportUpdate]

    public init(title: String, oneLiner: String, type: String, summary: String,
                topics: [String], keyPoints: [String], provider: String, model: String,
                generatedAt: String, updates: [ExportUpdate]) {
        self.title = title; self.oneLiner = oneLiner; self.type = type; self.summary = summary
        self.topics = topics; self.keyPoints = keyPoints
        self.provider = provider; self.model = model; self.generatedAt = generatedAt
        self.updates = updates
    }
}

public struct ExportUpdate: Sendable {
    public var oneLiner: String
    public var changes: [String]
    public var generatedAt: String

    public init(oneLiner: String, changes: [String], generatedAt: String) {
        self.oneLiner = oneLiner; self.changes = changes; self.generatedAt = generatedAt
    }
}

public enum CardExportFormat: String, Sendable, CaseIterable {
    case markdown
    case plainText

    public var fileExtension: String { self == .markdown ? "md" : "txt" }
    public var displayName: String { self == .markdown ? "Markdown" : "纯文本" }
}

/// Pure formatter producing Markdown or plain text. Output block order matches
/// the card's block order. Works with no summary and no tags.
public enum CardExportFormatter {

    public static func export(_ card: CardExportContent, as format: CardExportFormat) -> String {
        let md = format == .markdown
        var out: [String] = []

        out.append(heading(1, card.title.isEmpty ? "未命名笔记" : card.title, md: md))

        var meta: [String] = []
        if let f = card.folderName, !f.isEmpty { meta.append("文件夹:\(f)") }
        if let c = card.createdAt, !c.isEmpty { meta.append("创建:\(c)") }
        if let u = card.updatedAt, !u.isEmpty { meta.append("修改:\(u)") }
        if !card.tags.isEmpty {
            meta.append("标签:" + card.tags.map { md ? "#\($0)" : $0 }.joined(separator: " "))
        }
        if !meta.isEmpty { out.append(meta.joined(separator: md ? "  ·  " : " · ")) }

        for block in card.blocks.sorted(by: { $0.order < $1.order }) {
            if let section = blockSection(block, md: md) { out.append("") ; out.append(section) }
        }

        if let summary = card.summary {
            out.append("")
            out.append(heading(2, "AI 初始总结", md: md))
            if !summary.type.isEmpty { out.append(label("类型", summary.type, md: md)) }
            if !summary.oneLiner.isEmpty { out.append(summary.oneLiner) }
            if !summary.topics.isEmpty { out.append(label("主题", summary.topics.joined(separator: "、"), md: md)) }
            if !summary.keyPoints.isEmpty {
                out.append("要点:")
                for point in summary.keyPoints { out.append(listItem(point, md: md)) }
            }
            if !summary.summary.isEmpty { out.append(summary.summary) }
            let credit = "\(summary.provider) · \(summary.model) · \(summary.generatedAt)"
            out.append(md ? "_\(credit)_" : credit)

            if !summary.updates.isEmpty {
                out.append("")
                out.append(heading(2, "AI 更新记录", md: md))
                for update in summary.updates {
                    let line = update.oneLiner.isEmpty ? "内容有更新" : update.oneLiner
                    out.append((md ? "**" : "") + line + (md ? "**" : "") + "(\(update.generatedAt))")
                    for change in update.changes { out.append(listItem(change, md: md)) }
                }
            }
        }

        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    // MARK: - Section rendering

    static func blockSection(_ b: CardBlockContent, md: Bool) -> String? {
        func clean(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        switch b.kind {
        case .text:
            let raw = clean(b.text)
            guard !raw.isEmpty else { return nil }
            return md ? raw : MarkdownText.plainText(from: raw)
        case .audio:
            let t = clean(b.transcript)
            return label("录音转写", t.isEmpty ? "(无转写)" : t, md: md)
        case .image:
            let caption = clean(b.imageCaption)
            return label("图片", caption.isEmpty ? "(无说明)" : caption, md: md)
        case .file:
            let name = clean(b.fileName).isEmpty ? "未命名文档" : clean(b.fileName)
            var text = "\(name)\(clean(b.fileType).isEmpty ? "" : "(\(clean(b.fileType)))")"
            let extracted = clean(b.extractedText)
            if b.extractionUnavailable {
                text += "(暂不支持提取文字)"
            } else if !extracted.isEmpty {
                text += "\n" + String(extracted.prefix(500))
                if extracted.count > 500 { text += "…" }
            }
            return label("文档", text, md: md)
        case .link:
            let url = clean(b.url)
            guard !url.isEmpty else { return nil }
            let title = clean(b.linkTitle)
            var section = md
                ? "🔗 " + (title.isEmpty ? url : "[\(title)](\(url))")
                : "链接:" + (title.isEmpty ? url : "\(title) \(url)")
            let desc = clean(b.linkDescription)
            if !desc.isEmpty { section += "\n" + desc }
            return section
        }
    }

    // MARK: - Markdown/plain helpers

    private static func heading(_ level: Int, _ text: String, md: Bool) -> String {
        md ? String(repeating: "#", count: level) + " " + text : text
    }
    private static func label(_ name: String, _ value: String, md: Bool) -> String {
        md ? "**\(name):**\(value)" : "\(name):\(value)"
    }
    private static func listItem(_ text: String, md: Bool) -> String {
        md ? "- \(text)" : "• \(text)"
    }
}
