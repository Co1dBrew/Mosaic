import SwiftUI
import UIKit

/// A UITextView-backed editor for the lightweight rich-text (Markdown) block.
/// Provides a keyboard accessory toolbar that inserts/wraps Markdown around the
/// current selection (real selection handling, which pure SwiftUI lacks). Stores
/// plain Markdown source in the bound string.
struct RichMarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    var onChange: () -> Void = {}

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false                  // grow to fit inside the List
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        // 横向接受父视图给的宽度（见 `sizeThatFits`）。不设的话 `UITextView` 会用
        // 「整行不换行」的固有宽度去争取空间。
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.inputAccessoryView = context.coordinator.makeToolbar()
        context.coordinator.textView = textView
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
    }

    /// **既有缺陷的修复。** 不实现这个方法时，SwiftUI 只能用 `UITextView` 的固有尺寸，
    /// 而那是「整行不换行」的宽度 —— 一段长文本会横向铺出屏幕两侧，超出的部分看不见
    /// （在模拟器上实见）。这里按父视图给的宽度算高度，文本才会真正换行。
    ///
    /// 这条是在验证 5.10 落点高亮时发现的：块比屏幕还宽时，临时高亮的 8pt 外扩与
    /// 12pt 圆角全被挤出屏幕，看起来是一条通栏色块 —— 契约 §3.3 的几何在这种行上
    /// 根本无法成立。所以它虽然是既有缺陷，却挡着 5.10 的验收。
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width < .infinity else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitted.height, 30))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: RichMarkdownEditor
        weak var textView: UITextView?

        init(_ parent: RichMarkdownEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.onChange()
        }

        func makeToolbar() -> UIToolbar {
            let bar = UIToolbar()
            bar.sizeToFit()
            func item(_ symbol: String, _ action: Selector) -> UIBarButtonItem {
                UIBarButtonItem(image: UIImage(systemName: symbol), style: .plain, target: self, action: action)
            }
            bar.items = [
                item("textformat.size", #selector(heading)),
                item("bold", #selector(boldText)),
                item("italic", #selector(italicText)),
                item("list.bullet", #selector(bullet)),
                item("list.number", #selector(numbered)),
                item("minus", #selector(divider)),
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
            ]
            return bar
        }

        @objc private func done() { textView?.resignFirstResponder() }
        @objc private func boldText() { wrapSelection(with: "**", placeholder: "粗体") }
        @objc private func italicText() { wrapSelection(with: "*", placeholder: "斜体") }
        @objc private func heading() { prefixCurrentLine(with: "# ") }
        @objc private func bullet() { prefixCurrentLine(with: "- ") }
        @objc private func numbered() { prefixCurrentLine(with: "1. ") }
        @objc private func divider() { insert("\n---\n") }

        private func wrapSelection(with marker: String, placeholder: String) {
            guard let tv = textView else { return }
            let ns = tv.text as NSString
            let range = tv.selectedRange
            let selected = ns.substring(with: range)
            let inner = selected.isEmpty ? placeholder : selected
            let replacement = "\(marker)\(inner)\(marker)"
            tv.text = ns.replacingCharacters(in: range, with: replacement)
            let markerLen = (marker as NSString).length
            let innerLen = (inner as NSString).length
            // Select the inner text so the user can immediately overtype it.
            tv.selectedRange = NSRange(location: range.location + markerLen, length: innerLen)
            commit(tv)
        }

        private func prefixCurrentLine(with prefix: String) {
            guard let tv = textView else { return }
            let ns = tv.text as NSString
            let lineRange = ns.lineRange(for: NSRange(location: tv.selectedRange.location, length: 0))
            tv.text = ns.replacingCharacters(in: NSRange(location: lineRange.location, length: 0), with: prefix)
            tv.selectedRange = NSRange(location: tv.selectedRange.location + (prefix as NSString).length, length: 0)
            commit(tv)
        }

        private func insert(_ string: String) {
            guard let tv = textView else { return }
            let ns = tv.text as NSString
            let range = tv.selectedRange
            tv.text = ns.replacingCharacters(in: range, with: string)
            tv.selectedRange = NSRange(location: range.location + (string as NSString).length, length: 0)
            commit(tv)
        }

        private func commit(_ tv: UITextView) {
            parent.text = tv.text
            parent.onChange()
        }
    }
}
