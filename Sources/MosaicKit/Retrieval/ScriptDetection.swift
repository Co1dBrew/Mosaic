import Foundation

/// 判断一段文字里有没有汉字。
///
/// 检索里「有没有中文」决定走哪套向量空间（见 `EmbeddingRouter`）。
/// 只认汉字本身，不把日文假名、韩文、标点算进去 —— 那些单独出现时
/// 用英文本地模型或云端多语言模型都说得通，不算「必须中文模型」。
public enum ScriptDetection {

    /// CJK 统一汉字 + 扩展 A + 兼容汉字。覆盖简体 / 繁体日常用字。
    public static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { isHan($0) }
    }

    /// 标题、标签、块正文、OCR 等任何一处有汉字即视为「这篇笔记含中文」。
    public static func containsHan(title: String,
                                   tags: [String] = [],
                                   blocks: [CardBlockContent],
                                   extraTexts: [String] = []) -> Bool {
        if containsHan(title) { return true }
        if tags.contains(where: containsHan) { return true }
        if extraTexts.contains(where: containsHan) { return true }
        for block in blocks {
            if let extracted = RetrievableText.extract(from: block), containsHan(extracted.text) {
                return true
            }
        }
        return false
    }

    public static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v)
            || (0x3400...0x4DBF).contains(v)
            || (0xF900...0xFAFF).contains(v)
    }
}
