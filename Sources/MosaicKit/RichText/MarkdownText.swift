import Foundation

/// Lightweight Markdown helpers for the MVP rich-text text block (PRD §4.3.1).
/// Text blocks store Markdown-like source in `Block.text`; this extracts clean
/// plain text for AI summarization and search (so `#`, `*`, `-`, `---` don't
/// pollute summaries) and detects whether a block uses any formatting.
public enum MarkdownText {

    /// Strips Markdown syntax to readable plain text, preserving line structure.
    public static func plainText(from markdown: String) -> String {
        var outputLines: [String] = []
        for rawLine in markdown.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if isDivider(trimmed) { continue } // drop --- / *** / ___
            var line = stripLeading(rawLine, pattern: "^\\s{0,3}#{1,6}\\s+")          // heading
            line = stripLeading(line, pattern: "^\\s*([-*+]\\s+|\\d+[.)]\\s+)")        // list markers
            line = stripInline(line)
            outputLines.append(line)
        }
        let joined = outputLines.joined(separator: "\n")
        return collapseBlankLines(joined).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True if the text uses any supported lightweight formatting.
    public static func hasFormatting(_ markdown: String) -> Bool {
        for rawLine in markdown.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if isDivider(trimmed) { return true }
            if matches(rawLine, pattern: "^\\s{0,3}#{1,6}\\s+") { return true }       // heading
            if matches(rawLine, pattern: "^\\s*([-*+]\\s+|\\d+[.)]\\s+)") { return true } // list
            if matches(rawLine, pattern: "(\\*\\*|__).+?(\\*\\*|__)") { return true } // bold
            if matches(rawLine, pattern: "\\*(?=\\S)[^*\\n]+?(?<=\\S)\\*") { return true } // italic (no inner spaces)
            if matches(rawLine, pattern: "\\[[^\\]]+\\]\\([^)]*\\)") { return true }   // link
        }
        return false
    }

    // MARK: - Line parsing (for rendering)

    /// `# Heading` → (level, text); nil if not a heading.
    public static func headingLevel(of line: String) -> (level: Int, text: String)? {
        guard let groups = firstMatch(line, pattern: "^\\s{0,3}(#{1,6})\\s+(.*)$") else { return nil }
        return (groups[1].count, groups[2])
    }

    /// `- item` / `* item` / `+ item` → text; nil otherwise.
    public static func bulletContent(of line: String) -> String? {
        guard let groups = firstMatch(line, pattern: "^\\s*[-*+]\\s+(.*)$") else { return nil }
        return groups[1]
    }

    /// `1. item` / `2) item` → (number, text); nil otherwise.
    public static func orderedItem(of line: String) -> (number: Int, text: String)? {
        guard let groups = firstMatch(line, pattern: "^\\s*(\\d+)[.)]\\s+(.*)$"),
              let number = Int(groups[1]) else { return nil }
        return (number, groups[2])
    }

    // MARK: - Helpers

    public static func isDivider(_ s: String) -> Bool {
        guard s.count >= 3 else { return false }
        return s.allSatisfy { $0 == "-" } || s.allSatisfy { $0 == "*" } || s.allSatisfy { $0 == "_" }
    }

    static func stripInline(_ s: String) -> String {
        var line = s
        // Links [text](url) -> text
        line = replace(line, pattern: "\\[([^\\]]+)\\]\\([^)]*\\)", template: "$1")
        // Bold **text** / __text__
        line = replace(line, pattern: "(\\*\\*|__)(.+?)\\1", template: "$2")
        // Italic *text* / _text_
        line = replace(line, pattern: "(\\*|_)(.+?)\\1", template: "$2")
        // Inline code `text`
        line = replace(line, pattern: "`([^`]+)`", template: "$1")
        // Strikethrough ~~text~~
        line = replace(line, pattern: "~~(.+?)~~", template: "$1")
        return line
    }

    private static func replace(_ s: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }

    private static func stripLeading(_ s: String, pattern: String) -> String {
        replace(s, pattern: pattern, template: "")
    }

    private static func firstMatch(_ s: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let match = regex.firstMatch(in: s, range: range) else { return nil }
        var groups: [String] = []
        for i in 0..<match.numberOfRanges {
            if let r = Range(match.range(at: i), in: s) { groups.append(String(s[r])) }
            else { groups.append("") }
        }
        return groups
    }

    private static func matches(_ s: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)) != nil
    }

    private static func collapseBlankLines(_ s: String) -> String {
        replace(s, pattern: "\\n{3,}", template: "\n\n")
    }
}
