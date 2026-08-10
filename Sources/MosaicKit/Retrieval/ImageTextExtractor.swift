import Foundation

/// Result of running OCR over one image.
public struct ImageTextResult: Sendable, Equatable {
    public let text: String
    /// Mean recognition confidence in [0, 1], or 0 when the engine reports none.
    public let confidence: Double
    /// Language codes actually recognised, for diagnostics.
    public let languages: [String]

    public init(text: String, confidence: Double = 0, languages: [String] = []) {
        self.text = text
        self.confidence = confidence
        self.languages = languages
    }

    public static let empty = ImageTextResult(text: "", confidence: 0, languages: [])
}

public enum ImageTextExtractionError: Error, Equatable, Sendable {
    case assetMissing(String)
    case unsupportedFormat(String)
    case recognitionFailed(String)
    /// No OCR engine on this platform/toolchain.
    case unavailable
}

/// # OCR seam
///
/// Declared in MosaicKit; implemented in the app target with Vision.
///
/// Vision is not usable from the Command Line Tools toolchain that runs
/// `mosaic-checks`, so the protocol lives here (where the chunk pipeline needs it)
/// and `VisionImageTextExtractor` lives in the iOS app (where the SDK exists).
/// Same shape as `EmbeddingProvider`: the pipeline depends on the protocol, the
/// platform supplies the implementation.
public protocol ImageTextExtractor: Sendable {
    /// Identity of the recognition engine, mixed into diagnostics and — when it
    /// changes — a reason to re-extract.
    var engineIdentifier: String { get }
    /// - Parameter relativePath: media path as stored on `Block.imageRelativePath`.
    func extractText(fromRelativePath relativePath: String) async throws -> ImageTextResult
}

/// Always returns nothing. Used where OCR is deliberately not wanted (tests that
/// isolate other behaviour) — distinct from an extractor that *fails*, which
/// would exercise error handling instead.
public struct NoopImageTextExtractor: ImageTextExtractor {
    public let engineIdentifier = "noop"
    public init() {}
    public func extractText(fromRelativePath _: String) async throws -> ImageTextResult { .empty }
}

/// Canned results by path, for deterministic tests of the OCR → chunk → embed path.
public struct StubImageTextExtractor: ImageTextExtractor {
    public let engineIdentifier: String
    private let table: [String: ImageTextResult]
    private let failing: Set<String>

    public init(engineIdentifier: String = "stub-v1",
                table: [String: ImageTextResult] = [:],
                failing: Set<String> = []) {
        self.engineIdentifier = engineIdentifier
        self.table = table
        self.failing = failing
    }

    public func extractText(fromRelativePath relativePath: String) async throws -> ImageTextResult {
        if failing.contains(relativePath) {
            throw ImageTextExtractionError.recognitionFailed(relativePath)
        }
        return table[relativePath] ?? .empty
    }
}
