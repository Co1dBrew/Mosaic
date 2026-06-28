import Foundation
import MosaicKit

func runAggregatorChecks(_ r: CheckRunner) {
    r.suite("CardContentAggregator.aggregate")

    let blocks = [
        CardBlockContent(id: "1", order: 0, kind: .text, text: "手打的文字内容"),
        CardBlockContent(id: "2", order: 1, kind: .audio, transcript: "这是录音转写"),
        CardBlockContent(id: "3", order: 2, kind: .audio, transcript: nil),
        CardBlockContent(id: "4", order: 3, kind: .file, fileName: "report.pdf", fileType: "PDF", extractedText: "文档正文"),
        CardBlockContent(id: "5", order: 4, kind: .file, fileName: "a.ppt", fileType: "PPT", extractionUnavailable: true),
        CardBlockContent(id: "6", order: 5, kind: .link, url: "https://x.test", linkTitle: "标题T", linkDescription: "描述D"),
        CardBlockContent(id: "7", order: 6, kind: .image, imageCaption: "一只猫"),
        CardBlockContent(id: "8", order: 7, kind: .image, imageCaption: nil)
    ]
    let text = CardContentAggregator.aggregate(title: "我的标题", blocks: blocks)

    r.expect(text.contains("【标题】我的标题"), "includes title")
    r.expect(text.contains("【文字】"), "includes text section")
    r.expect(text.contains("这是录音转写"), "includes transcript")
    r.expect(text.contains("(无转写文字)"), "marks empty transcript")
    r.expect(text.contains("report.pdf"), "includes doc name")
    r.expect(text.contains("文档正文"), "includes extracted text")
    r.expect(text.contains("暂不支持提取文字"), "marks unsupported doc")
    r.expect(text.contains("https://x.test"), "includes link url")
    r.expect(text.contains("【图片说明】一只猫"), "includes image caption")
    r.expect(text.contains("(见所附图片)"), "uncaptioned image referenced")

    // Order preserved: 标题 before 文字 before 录音
    if let titleIdx = text.range(of: "【标题】"), let textIdx = text.range(of: "【文字】") {
        r.expect(titleIdx.lowerBound < textIdx.lowerBound, "title precedes text")
    }

    // Empty card
    r.expectEqual(CardContentAggregator.aggregate(title: nil, blocks: []), "", "empty card -> empty string")

    r.suite("CardContentAggregator truncation")
    let long = String(repeating: "段", count: 100)
    let limits = AggregationLimits(perDocumentChars: 20, maxImages: 6)
    let docBlocks = [CardBlockContent(id: "1", order: 0, kind: .file, fileName: "big.pdf", fileType: "PDF", extractedText: long)]
    let truncated = CardContentAggregator.aggregate(title: nil, blocks: docBlocks, limits: limits)
    r.expect(truncated.contains("已截断"), "long doc truncated with notice")
    r.expect(truncated.count < long.count, "truncated text shorter than original")

    r.suite("CardContentAggregator.changeSetText")
    let diff = CardDiff(
        added: [CardBlockContent(id: "1", order: 0, kind: .text, text: "新增内容")],
        modified: [CardBlockContent(id: "2", order: 1, kind: .link, url: "https://y.test", linkTitle: "改了")],
        deleted: [DeletedBlock(id: "3", kind: .audio, brief: "旧录音")]
    )
    let cs = CardContentAggregator.changeSetText(diff: diff)
    r.expect(cs.contains("【新增】"), "labels additions")
    r.expect(cs.contains("新增内容"), "includes added content")
    r.expect(cs.contains("【修改】"), "labels modifications")
    r.expect(cs.contains("【删除】"), "labels deletions")
    r.expect(cs.contains("旧录音"), "describes deleted block via brief")
}
