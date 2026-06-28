import Foundation

/// The five content block types (PRD §4.3 / §8).
public enum BlockKind: String, Codable, Sendable, CaseIterable {
    case text
    case image
    case audio
    case file
    case link
}

/// A platform-agnostic snapshot of a single block's content, used for hashing,
/// diffing, and aggregation. The iOS app builds these from its SwiftData models
/// so that MosaicKit never depends on SwiftData or UIKit.
public struct CardBlockContent: Sendable, Equatable, Identifiable {
    public let id: String
    public let order: Int
    public let kind: BlockKind

    // Text block
    public var text: String?

    // Image block
    public var imageCaption: String?
    /// Stable identifier of the image asset (e.g. file name) — lets the diff
    /// detect that the underlying image changed even if the caption did not.
    public var imageAssetRef: String?

    // Audio block
    public var transcript: String?
    public var audioDurationSec: Double?
    public var audioAssetRef: String?

    // File / document block
    public var fileName: String?
    public var fileType: String?
    public var extractedText: String?
    /// True when text extraction is not available for this document type (PRD §4.3.4).
    public var extractionUnavailable: Bool

    // Link block
    public var url: String?
    public var linkTitle: String?
    public var linkDescription: String?

    public init(
        id: String,
        order: Int,
        kind: BlockKind,
        text: String? = nil,
        imageCaption: String? = nil,
        imageAssetRef: String? = nil,
        transcript: String? = nil,
        audioDurationSec: Double? = nil,
        audioAssetRef: String? = nil,
        fileName: String? = nil,
        fileType: String? = nil,
        extractedText: String? = nil,
        extractionUnavailable: Bool = false,
        url: String? = nil,
        linkTitle: String? = nil,
        linkDescription: String? = nil
    ) {
        self.id = id
        self.order = order
        self.kind = kind
        self.text = text
        self.imageCaption = imageCaption
        self.imageAssetRef = imageAssetRef
        self.transcript = transcript
        self.audioDurationSec = audioDurationSec
        self.audioAssetRef = audioAssetRef
        self.fileName = fileName
        self.fileType = fileType
        self.extractedText = extractedText
        self.extractionUnavailable = extractionUnavailable
        self.url = url
        self.linkTitle = linkTitle
        self.linkDescription = linkDescription
    }

    /// Whether this block is an image, used when gathering vision inputs.
    public var isImage: Bool { kind == .image }
}
