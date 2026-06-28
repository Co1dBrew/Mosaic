import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Imports documents into the sandbox and extracts text for AI summary
/// (PRD §4.3.4 / §7.1). PDF + plain text are supported in MVP; other types are
/// saved and previewable but flagged as text-extraction-unavailable.
struct DocumentImporter {
    let mediaStore: MediaStore

    init(mediaStore: MediaStore = .shared) {
        self.mediaStore = mediaStore
    }

    struct Result {
        let relativePath: String
        let fileName: String
        let fileType: String
        let extractedText: String
        let extractionUnavailable: Bool
    }

    /// Copies the picked document into the sandbox and extracts text when possible.
    /// Handles security-scoped URLs from the document picker.
    func importDocument(from url: URL) throws -> Result {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let utType = UTType(filenameExtension: ext)
        let typeLabel = Self.typeLabel(for: utType, ext: ext)

        let relativePath = try mediaStore.importFile(from: url, preferredExtension: ext)
        let storedURL = mediaStore.absoluteURL(for: relativePath)

        let (text, unavailable) = Self.extractText(from: storedURL, utType: utType, ext: ext)
        return Result(
            relativePath: relativePath,
            fileName: fileName,
            fileType: typeLabel,
            extractedText: text,
            extractionUnavailable: unavailable
        )
    }

    /// Returns (extractedText, extractionUnavailable).
    static func extractText(from url: URL, utType: UTType?, ext: String) -> (String, Bool) {
        if utType == .pdf || ext == "pdf" {
            if let doc = PDFDocument(url: url) {
                let text = doc.string ?? ""
                return (text, false)
            }
            return ("", false) // a PDF with no extractable text (e.g. scanned) — still "supported"
        }
        if utType?.conforms(to: .plainText) == true || ext == "txt" || ext == "md" {
            if let data = try? Data(contentsOf: url) {
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                return (text, false)
            }
            return ("", true)
        }
        // Word / PPT / Excel etc.: saved & previewable, extraction not yet supported.
        return ("", true)
    }

    static func typeLabel(for utType: UTType?, ext: String) -> String {
        if let utType {
            if utType == .pdf { return "PDF" }
            if utType.conforms(to: .plainText) { return "文本" }
            if utType == .rtf { return "RTF" }
            if let desc = utType.localizedDescription { return desc }
        }
        return ext.isEmpty ? "文档" : ext.uppercased()
    }
}
