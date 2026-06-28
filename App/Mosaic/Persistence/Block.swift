import Foundation
import SwiftData
import MosaicKit

/// A single content block. One model holds the payload for all five kinds
/// (PRD §8 "Block 按 type 区分 payload"), which keeps the schema flat and
/// CloudKit-friendly. Media bytes live in the app sandbox; only relative paths
/// are stored here.
@Model
final class Block {
    var id: UUID = UUID()
    var order: Int = 0
    /// Stored raw value of `BlockKind`.
    var kindRaw: String = BlockKind.text.rawValue
    var createdAt: Date = Date()

    var card: Card?

    // Text
    var text: String = ""

    // Image
    var imageRelativePath: String = ""
    var thumbnailRelativePath: String = ""
    var imageSourceRaw: String = ""        // "camera" | "library"
    var caption: String = ""

    // Audio
    var audioRelativePath: String = ""
    var durationSec: Double = 0
    var transcript: String = ""
    var waveformSamples: [Double] = []

    // File / document
    var fileRelativePath: String = ""
    var fileName: String = ""
    var fileType: String = ""              // human label, e.g. "PDF"
    var extractedText: String = ""
    var extractionUnavailable: Bool = false

    // Link
    var url: String = ""
    var linkTitle: String = ""
    var linkDescription: String = ""

    init(kind: BlockKind, order: Int) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.order = order
        self.createdAt = Date()
    }

    var kind: BlockKind {
        get { BlockKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var isEffectivelyEmpty: Bool {
        switch kind {
        case .text:  return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image: return imageRelativePath.isEmpty
        case .audio: return audioRelativePath.isEmpty
        case .file:  return fileRelativePath.isEmpty
        case .link:  return url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Adapts the SwiftData model into the MosaicKit value type used for hashing,
    /// diffing, and aggregation. Asset refs use the relative path so replacing
    /// media is detected as a content change.
    func toContent() -> CardBlockContent {
        CardBlockContent(
            id: id.uuidString,
            order: order,
            kind: kind,
            text: kind == .text ? text : nil,
            imageCaption: kind == .image ? caption : nil,
            imageAssetRef: kind == .image ? imageRelativePath : nil,
            transcript: kind == .audio ? transcript : nil,
            audioDurationSec: kind == .audio ? durationSec : nil,
            audioAssetRef: kind == .audio ? audioRelativePath : nil,
            fileName: kind == .file ? fileName : nil,
            fileType: kind == .file ? fileType : nil,
            extractedText: kind == .file ? extractedText : nil,
            extractionUnavailable: kind == .file ? extractionUnavailable : false,
            url: kind == .link ? url : nil,
            linkTitle: kind == .link ? linkTitle : nil,
            linkDescription: kind == .link ? linkDescription : nil
        )
    }
}

enum ImageSource: String {
    case camera
    case library
}
