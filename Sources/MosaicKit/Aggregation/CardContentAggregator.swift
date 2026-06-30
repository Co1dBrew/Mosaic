import Foundation

/// Limits applied when aggregating content for AI requests (PRD §4.3.3, §11).
public struct AggregationLimits: Sendable {
    /// Max characters of extracted text included per document before truncation.
    public var perDocumentChars: Int
    /// Max number of images attached as vision input per request.
    public var maxImages: Int

    public init(perDocumentChars: Int = 8000, maxImages: Int = 6) {
        self.perDocumentChars = perDocumentChars
        self.maxImages = maxImages
    }

    public static let `default` = AggregationLimits()
}

/// Builds the text payloads sent to the AI (PRD §4.6). Pure and synchronous so
/// it is fully unit-testable; image bytes are gathered separately by the app.
public enum CardContentAggregator {

    /// Aggregates the whole card into a single text block for the base summary,
    /// preserving block order and labeling each section (PRD §4.6 step 1–6).
    public static func aggregate(
        title: String?,
        blocks: [CardBlockContent],
        limits: AggregationLimits = .default
    ) -> String {
        var sections: [String] = []

        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("【标题】\(title.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        for block in blocks.sorted(by: { $0.order < $1.order }) {
            if let section = section(for: block, limits: limits) {
                sections.append(section)
            }
        }
        return sections.joined(separator: "\n\n")
    }

    /// Builds the (B) change-set text for the update summary (PRD §5.3),
    /// labeling additions, modifications, and deletions.
    public static func changeSetText(
        diff: CardDiff,
        limits: AggregationLimits = .default
    ) -> String {
        var lines: [String] = []

        for block in diff.added.sorted(by: { $0.order < $1.order }) {
            if let body = section(for: block, limits: limits) {
                lines.append("【新增】\n\(body)")
            }
        }
        for block in diff.modified.sorted(by: { $0.order < $1.order }) {
            if let body = section(for: block, limits: limits) {
                lines.append("【修改】\n\(body)")
            }
        }
        for del in diff.deleted {
            lines.append("【删除】\(label(for: del.kind)):\(del.brief)")
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Section rendering

    /// Renders one block as a labeled text section, or `nil` if it has no
    /// AI-relevant text (e.g. an uncaptioned image, whose bytes go as vision input).
    static func section(for block: CardBlockContent, limits: AggregationLimits) -> String? {
        func clean(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

        switch block.kind {
        case .text:
            // Text blocks store lightweight Markdown — extract plain text so the
            // AI summary isn't polluted by #, *, -, --- markers (PRD §4.3.1).
            let t = MarkdownText.plainText(from: block.text ?? "")
            return t.isEmpty ? nil : "【文字】\n\(t)"

        case .audio:
            let t = clean(block.transcript)
            if t.isEmpty {
                return "【录音转写】(无转写文字)"
            }
            return "【录音转写】\n\(t)"

        case .file:
            let name = clean(block.fileName)
            let type = clean(block.fileType)
            let header = "【文档:\(name.isEmpty ? "未命名" : name)\(type.isEmpty ? "" : " · \(type)")】"
            if block.extractionUnavailable {
                return "\(header)\n(该文档类型暂不支持提取文字)"
            }
            let extracted = clean(block.extractedText)
            if extracted.isEmpty {
                return "\(header)\n(未提取到文字)"
            }
            return "\(header)\n\(truncate(extracted, limit: limits.perDocumentChars))"

        case .link:
            let url = clean(block.url)
            guard !url.isEmpty else { return nil }
            var parts = ["网址:\(url)"]
            if !clean(block.linkTitle).isEmpty { parts.append("标题:\(clean(block.linkTitle))") }
            if !clean(block.linkDescription).isEmpty { parts.append("描述:\(clean(block.linkDescription))") }
            return "【链接】\n" + parts.joined(separator: "\n")

        case .image:
            let caption = clean(block.imageCaption)
            if caption.isEmpty {
                return "【图片】(见所附图片)"
            }
            return "【图片说明】\(caption)"
        }
    }

    private static func label(for kind: BlockKind) -> String {
        switch kind {
        case .text: return "文字"
        case .image: return "图片"
        case .audio: return "录音"
        case .file: return "文档"
        case .link: return "链接"
        }
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n…(文档过长,已截断)"
    }
}
