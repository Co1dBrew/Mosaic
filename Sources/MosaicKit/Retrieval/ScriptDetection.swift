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

    /// 有没有拉丁字母。
    ///
    /// 用来判断「这个库是不是**双语**的」—— 只有双语库才存在「本地一次只覆盖一种语言」
    /// 这个问题（`EmbeddingRouter.shouldOfferCloudUpgrade`）。
    ///
    /// 只认 A–Z / a–z 与带变音符的拉丁扩展。**刻意不认数字与标点** ——
    /// 一篇纯中文笔记里出现 `2026` 或 `CS5330` 的数字部分很常见，
    /// 把它算成「含英文」会让提示在纯中文库上冒出来，那正是要避免的骚扰。
    public static func containsLatin(_ text: String) -> Bool {
        text.unicodeScalars.contains { isLatinLetter($0) }
    }

    /// 与 `containsHan(title:tags:blocks:extraTexts:)` 同一套遍历口径。
    public static func containsLatin(title: String,
                                     tags: [String] = [],
                                     blocks: [CardBlockContent],
                                     extraTexts: [String] = []) -> Bool {
        if containsLatin(title) { return true }
        if tags.contains(where: containsLatin) { return true }
        if extraTexts.contains(where: containsLatin) { return true }
        for block in blocks {
            if let extracted = RetrievableText.extract(from: block), containsLatin(extracted.text) {
                return true
            }
        }
        return false
    }

    public static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x0041...0x005A).contains(v)      // A–Z
            || (0x0061...0x007A).contains(v)      // a–z
            || (0x00C0...0x024F).contains(v)      // Latin-1 补充 + 扩展 A/B（café 之类）
    }

    public static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v)
            || (0x3400...0x4DBF).contains(v)
            || (0xF900...0xFAFF).contains(v)
    }
}
