import Foundation
import MosaicKit

/// Bridges SwiftData `Card` → MosaicKit `CardExportContent` and writes the
/// formatted export to a temporary file for the share sheet. Pure formatting
/// lives in `CardExportFormatter`; nothing is uploaded (PRD privacy).
enum CardExportService {

    static func content(for card: Card) -> CardExportContent {
        var summary: ExportSummary?
        if let s = card.summary, s.hasBase {
            let updates = s.sortedUpdateLogs.map {
                ExportUpdate(oneLiner: $0.updateOneLiner, changes: $0.changes, generatedAt: Format.dateTime($0.generatedAt))
            }
            summary = ExportSummary(
                title: s.baseTitle, oneLiner: s.baseOneLiner, type: s.baseType, summary: s.baseSummary,
                topics: s.baseTopics, keyPoints: s.baseKeyPoints,
                provider: s.baseProviderUsed, model: s.baseModelUsed,
                generatedAt: Format.dateTime(s.baseGeneratedAt), updates: updates
            )
        }
        return CardExportContent(
            title: card.displayTitle,
            folderName: card.folder?.name,
            createdAt: Format.dateTime(card.createdAt),
            updatedAt: Format.dateTime(card.updatedAt),
            tags: card.tags,
            blocks: card.blockContents(),
            summary: summary
        )
    }

    static func text(for card: Card, format: CardExportFormat) -> String {
        CardExportFormatter.export(content(for: card), as: format)
    }

    /// Writes the export to a temp file and returns its URL (nice filename for
    /// "Save to Files" / sharing).
    static func writeTempFile(for card: Card, format: CardExportFormat) throws -> URL {
        let string = text(for: card, format: format)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(sanitizedFileName(card.displayTitle)).\(format.fileExtension)")
        try Data(string.utf8).write(to: url, options: .atomic)
        return url
    }

    private static func sanitizedFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "笔记" : trimmed
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return base.components(separatedBy: invalid).joined(separator: "_")
    }
}
