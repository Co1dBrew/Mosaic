import Foundation
import MosaicKit

func runExportChecks(_ r: CheckRunner) {
    r.suite("CardExportFormatter — structure & order")

    let blocks = [
        CardBlockContent(id: "1", order: 0, kind: .text, text: "# 小标题\n正文**重点**"),
        CardBlockContent(id: "2", order: 1, kind: .audio, transcript: "这是录音转写"),
        CardBlockContent(id: "3", order: 2, kind: .file, fileName: "report.pdf", fileType: "PDF", extractedText: "文档正文摘要"),
        CardBlockContent(id: "4", order: 3, kind: .link, url: "https://x.test", linkTitle: "标题T", linkDescription: "描述D"),
        CardBlockContent(id: "5", order: 4, kind: .image, imageCaption: "一只猫")
    ]
    let summary = ExportSummary(
        title: "周三评审", oneLiner: "概述一句话", type: "会议记录", summary: "整体总结段落",
        topics: ["产品", "排期"], keyPoints: ["要点一", "要点二"],
        provider: "Kimi", model: "moonshot-v1-8k", generatedAt: "2026-06-29 10:00",
        updates: [ExportUpdate(oneLiner: "改了排期", changes: ["新增A", "删除B"], generatedAt: "2026-06-29 12:00")]
    )
    let card = CardExportContent(
        title: "周三产品评审会要点", folderName: "工作",
        createdAt: "2026-06-29 09:00", updatedAt: "2026-06-29 12:00",
        tags: ["工作", "产品评审"], blocks: blocks, summary: summary
    )

    let markdown = CardExportFormatter.export(card, as: .markdown)
    r.expect(markdown.hasPrefix("# 周三产品评审会要点"), "markdown starts with H1 title")
    r.expect(markdown.contains("文件夹:工作"), "includes folder")
    r.expect(markdown.contains("#工作") && markdown.contains("#产品评审"), "includes tags as #tags")
    r.expect(markdown.contains("录音转写") && markdown.contains("这是录音转写"), "includes transcript")
    r.expect(markdown.contains("report.pdf") && markdown.contains("文档正文摘要"), "includes file + extracted excerpt")
    r.expect(markdown.contains("[标题T](https://x.test)"), "link as markdown")
    r.expect(markdown.contains("一只猫"), "image caption")
    r.expect(markdown.contains("AI 初始总结") && markdown.contains("整体总结段落"), "includes base summary")
    r.expect(markdown.contains("AI 更新记录") && markdown.contains("改了排期"), "includes update log")

    // Block order preserved: audio transcript appears before the link section
    if let aIdx = markdown.range(of: "这是录音转写"), let lIdx = markdown.range(of: "标题T") {
        r.expect(aIdx.lowerBound < lIdx.lowerBound, "block order preserved (audio before link)")
    }

    r.suite("CardExportFormatter — plain text strips markdown")

    let plain = CardExportFormatter.export(card, as: .plainText)
    r.expect(!plain.contains("# "), "no heading markers in plain text")
    r.expect(plain.contains("正文重点") && !plain.contains("**"), "text block markdown stripped")
    r.expect(plain.contains("标签:工作 产品评审"), "tags plain (no #)")
    r.expect(plain.contains("整体总结段落"), "summary present in plain text")

    r.suite("CardExportFormatter — minimal / empty")

    let empty = CardExportContent(title: "")
    let emptyMd = CardExportFormatter.export(empty, as: .markdown)
    r.expect(emptyMd.contains("未命名笔记"), "empty card -> placeholder title, still exports")

    let noSummary = CardExportContent(
        title: "只有文字", tags: [],
        blocks: [CardBlockContent(id: "1", order: 0, kind: .text, text: "纯文字内容")],
        summary: nil
    )
    let noSummaryMd = CardExportFormatter.export(noSummary, as: .markdown)
    r.expect(noSummaryMd.contains("纯文字内容") && !noSummaryMd.contains("AI 初始总结"), "exports without summary")
}
