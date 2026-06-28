import Foundation
import CryptoKit

/// Computes a stable content fingerprint for a block (PRD §4.5, §7.1
/// "块 ID → 内容 hash"). Order is intentionally excluded: reordering a block
/// does not change *what* was recorded, so it should not trigger an update.
public enum ContentHasher {

    /// Canonical, order-independent string describing a block's content.
    public static func canonicalString(for block: CardBlockContent) -> String {
        func n(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        switch block.kind {
        case .text:
            return "text|\(n(block.text))"
        case .image:
            return "image|ref=\(n(block.imageAssetRef))|caption=\(n(block.imageCaption))"
        case .audio:
            return "audio|ref=\(n(block.audioAssetRef))|transcript=\(n(block.transcript))"
        case .file:
            return "file|name=\(n(block.fileName))|type=\(n(block.fileType))|text=\(n(block.extractedText))|unavail=\(block.extractionUnavailable)"
        case .link:
            return "link|url=\(n(block.url))|title=\(n(block.linkTitle))|desc=\(n(block.linkDescription))"
        }
    }

    public static func hash(for block: CardBlockContent) -> String {
        hash(of: canonicalString(for: block))
    }

    public static func hash(of string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// A short human-readable description of a block, stored in the snapshot so
    /// deletions can be described after the block itself is gone.
    public static func brief(for block: CardBlockContent, maxLen: Int = 40) -> String {
        func clip(_ s: String?) -> String {
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count > maxLen else { return t }
            return String(t.prefix(maxLen)) + "…"
        }
        switch block.kind {
        case .text:  return clip(block.text)
        case .image: return clip(block.imageCaption).isEmpty ? "图片" : "图片:\(clip(block.imageCaption))"
        case .audio: return clip(block.transcript).isEmpty ? "录音" : "录音:\(clip(block.transcript))"
        case .file:  return "文档:\(clip(block.fileName))"
        case .link:  return "链接:\(clip(block.linkTitle).isEmpty ? clip(block.url) : clip(block.linkTitle))"
        }
    }

    public static func descriptor(for block: CardBlockContent) -> BlockDescriptor {
        let textLength = block.kind == .text
            ? (block.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count
            : 0
        return BlockDescriptor(hash: hash(for: block), kind: block.kind, brief: brief(for: block), textLength: textLength)
    }
}
