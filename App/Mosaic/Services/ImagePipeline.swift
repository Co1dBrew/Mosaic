import Foundation
#if canImport(UIKit)
import UIKit
#endif
import MosaicKit

/// Image import, thumbnailing, and vision-payload preparation (PRD §4.3.3 / §5.4).
/// All work is synchronous and CPU-bound; call from a background task so it never
/// blocks the main thread (PRD §6.3).
struct ImagePipeline {
    /// Long edge for images sent to the AI (PRD §4.3.3 "长边 ≤1568px").
    static let aiLongEdge: CGFloat = 1568
    /// Long edge for the stored full image (bounds sandbox size).
    static let fullLongEdge: CGFloat = 2048
    /// Long edge for list thumbnails.
    static let thumbnailLongEdge: CGFloat = 400

    let mediaStore: MediaStore

    init(mediaStore: MediaStore = .shared) {
        self.mediaStore = mediaStore
    }

    #if canImport(UIKit)
    struct ImportResult {
        let imageRelativePath: String
        let thumbnailRelativePath: String
    }

    /// Stores a full (bounded) image plus a thumbnail, returning their paths.
    func importImage(_ image: UIImage) throws -> ImportResult {
        let full = Self.resize(image, longEdge: Self.fullLongEdge)
        let thumb = Self.resize(image, longEdge: Self.thumbnailLongEdge)
        guard let fullData = full.jpegData(compressionQuality: 0.85),
              let thumbData = thumb.jpegData(compressionQuality: 0.7) else {
            throw ImageError.encodingFailed
        }
        let imagePath = try mediaStore.write(fullData, kind: .image, ext: "jpg")
        let thumbPath = try mediaStore.write(thumbData, kind: .thumbnail, ext: "jpg")
        return ImportResult(imageRelativePath: imagePath, thumbnailRelativePath: thumbPath)
    }

    /// Loads a stored image and prepares a compressed base64 vision payload.
    func aiImage(forRelativePath relativePath: String) -> AIImage? {
        let url = mediaStore.absoluteURL(for: relativePath)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        let resized = Self.resize(image, longEdge: Self.aiLongEdge)
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return nil }
        return AIImage(base64: jpeg.base64EncodedString(), mimeType: "image/jpeg")
    }

    /// Downscales an image so its longest edge is at most `longEdge`, preserving
    /// aspect ratio. Never upscales.
    static func resize(_ image: UIImage, longEdge: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > longEdge, maxSide > 0 else { return image }
        let scale = longEdge / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
    #endif

    enum ImageError: LocalizedError {
        case encodingFailed
        var errorDescription: String? {
            switch self { case .encodingFailed: return "图片处理失败,请重试。" }
        }
    }
}
