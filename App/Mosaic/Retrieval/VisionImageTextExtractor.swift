import Foundation
import MosaicKit
#if canImport(Vision)
import Vision
#endif
#if canImport(UIKit)
import UIKit
#endif

/// # IG-1 — Image OCR
///
/// Closes the corpus gap: PRD v1.0 lists Image OCR Text as a Goal 1 retrieval
/// source, and until now image blocks contributed only their caption.
///
/// On-device Vision, so it costs nothing per image and works offline. Runs
/// **off the main actor** — recognition on a large photo is tens of milliseconds
/// and must not touch the UI thread.
///
/// ## Scope, deliberately narrow
///
/// Printed Chinese and English (`zh-Hans`, `zh-Hant`, `en-US`), `.accurate`.
/// **Handwriting is not supported** — Vision's handwriting quality for Chinese is
/// poor enough that indexing its output would inject noise into the corpus, and
/// noise in the index is worse than a missing source: it produces confident wrong
/// matches instead of no match.
struct VisionImageTextExtractor: ImageTextExtractor {

    let engineIdentifier: String
    private let mediaStore: MediaStore
    /// Recognitions below this are discarded. A low-confidence read of a blurry
    /// photo is usually garbage characters, which is worse than no text at all.
    private let minimumConfidence: Float

    init(mediaStore: MediaStore = .shared,
         minimumConfidence: Float = 0.3,
         engineIdentifier: String = "vision-accurate-v1") {
        self.mediaStore = mediaStore
        self.minimumConfidence = minimumConfidence
        self.engineIdentifier = engineIdentifier
    }

    func extractText(fromRelativePath relativePath: String) async throws -> ImageTextResult {
        #if canImport(Vision) && canImport(UIKit)
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImageTextExtractionError.assetMissing("empty path") }

        guard mediaStore.fileExists(trimmed) else {
            throw ImageTextExtractionError.assetMissing(trimmed)
        }
        let url = mediaStore.absoluteURL(for: trimmed)

        let minimumConfidence = self.minimumConfidence
        return try await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data),
                  let cgImage = image.cgImage else {
                throw ImageTextExtractionError.unsupportedFormat(trimmed)
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do { try handler.perform([request]) }
            catch { throw ImageTextExtractionError.recognitionFailed(error.localizedDescription) }

            guard let observations = request.results, !observations.isEmpty else {
                return ImageTextResult.empty
            }

            var lines: [String] = []
            var confidences: [Float] = []
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                guard candidate.confidence >= minimumConfidence else { continue }
                let line = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                lines.append(line)
                confidences.append(candidate.confidence)
            }

            guard !lines.isEmpty else { return ImageTextResult.empty }
            let mean = confidences.reduce(0, +) / Float(confidences.count)
            // Newline-joined: Vision returns one observation per visual line, and
            // preserving those breaks keeps table-ish images (schedules, forms)
            // readable instead of collapsing them into one run-on string.
            return ImageTextResult(text: lines.joined(separator: "\n"),
                                   confidence: Double(mean),
                                   languages: request.recognitionLanguages)
        }.value
        #else
        throw ImageTextExtractionError.unavailable
        #endif
    }
}
