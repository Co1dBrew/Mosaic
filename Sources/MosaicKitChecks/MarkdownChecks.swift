import Foundation
import MosaicKit

func runMarkdownChecks(_ r: CheckRunner) {
    r.suite("MarkdownText.plainText")

    r.expectEqual(MarkdownText.plainText(from: "# 标题"), "标题", "heading marker stripped")
    r.expectEqual(MarkdownText.plainText(from: "### Heading 3"), "Heading 3", "h3 stripped")
    r.expectEqual(MarkdownText.plainText(from: "- 项目一"), "项目一", "bullet stripped")
    r.expectEqual(MarkdownText.plainText(from: "* 项目二"), "项目二", "star bullet stripped")
    r.expectEqual(MarkdownText.plainText(from: "1. 第一条"), "第一条", "ordered marker stripped")
    r.expectEqual(MarkdownText.plainText(from: "这是**粗体**字"), "这是粗体字", "bold stripped")
    r.expectEqual(MarkdownText.plainText(from: "这是*斜体*字"), "这是斜体字", "italic stripped")
    r.expectEqual(MarkdownText.plainText(from: "看 [文档](https://x.test) 链接"), "看 文档 链接", "link -> text")
    r.expectEqual(MarkdownText.plainText(from: "`code` 行"), "code 行", "inline code stripped")

    // Divider dropped
    r.expectEqual(MarkdownText.plainText(from: "上\n---\n下"), "上\n下", "divider line removed")

    // Plain text unchanged
    r.expectEqual(MarkdownText.plainText(from: "普通文字 plain text"), "普通文字 plain text", "plain text unchanged")

    // Mixed multi-line document
    let doc = """
    # 会议纪要
    今天讨论了**排期**与分工
    - 确定下周三上线
    - 新增三位*负责人*
    ---
    详见 [文档](https://x.test)
    """
    let plain = MarkdownText.plainText(from: doc)
    r.expect(plain.contains("会议纪要") && !plain.contains("#"), "heading text kept, marker gone")
    r.expect(plain.contains("排期") && !plain.contains("**"), "bold text kept, markers gone")
    r.expect(plain.contains("确定下周三上线") && !plain.contains("- "), "list text kept, markers gone")
    r.expect(!plain.contains("---"), "divider removed from plain text")
    r.expect(plain.contains("文档") && !plain.contains("https://x.test"), "link text kept, url removed")

    r.suite("MarkdownText.hasFormatting")

    r.expect(MarkdownText.hasFormatting("# 标题"), "heading -> formatted")
    r.expect(MarkdownText.hasFormatting("- 列表"), "bullet -> formatted")
    r.expect(MarkdownText.hasFormatting("有**粗体**"), "bold -> formatted")
    r.expect(MarkdownText.hasFormatting("分隔\n---\n线"), "divider -> formatted")
    r.expect(MarkdownText.hasFormatting("[链接](https://x)"), "link -> formatted")
    r.expect(!MarkdownText.hasFormatting("就是普通文字"), "plain -> not formatted")
    r.expect(!MarkdownText.hasFormatting("a * b * c 不是斜体"), "spaced asterisks not treated as italic")

    r.suite("MarkdownText line parsing")

    r.expectEqual(MarkdownText.headingLevel(of: "## 二级标题")?.level, 2, "heading level")
    r.expectEqual(MarkdownText.headingLevel(of: "## 二级标题")?.text, "二级标题", "heading text")
    r.expectNil(MarkdownText.headingLevel(of: "普通文字"), "non-heading -> nil")
    r.expectEqual(MarkdownText.bulletContent(of: "- 列表项"), "列表项", "bullet content")
    r.expectEqual(MarkdownText.bulletContent(of: "* 星号项"), "星号项", "star bullet content")
    r.expectNil(MarkdownText.bulletContent(of: "不是列表"), "non-bullet -> nil")
    r.expectEqual(MarkdownText.orderedItem(of: "3. 第三")?.number, 3, "ordered number")
    r.expectEqual(MarkdownText.orderedItem(of: "3. 第三")?.text, "第三", "ordered text")
    r.expect(MarkdownText.isDivider("---"), "--- is divider")
    r.expect(!MarkdownText.isDivider("-"), "single dash not divider")
}
