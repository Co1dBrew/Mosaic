import Foundation

/// Manages media files in the app sandbox (PRD §4.3 "原图存本地沙盒", §6.1).
///
/// Files are stored under Application Support/Media/<kind>/ and referenced by a
/// relative path so the database stays portable. NOTE: binary media is not yet
/// synced via CloudKit assets — only the SwiftData metadata syncs in this MVP
/// (see PRD §10.1 sequencing). This is the seam where CloudKit asset sync will
/// be added.
// Its only stored state is an immutable `let root: URL`, and FileManager calls
// are thread-safe, so it is safe to use across concurrency domains.
final class MediaStore: @unchecked Sendable {
    static let shared = MediaStore()

    enum Kind: String {
        case audio, image, thumbnail, file
    }

    let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )) ?? FileManager.default.temporaryDirectory
            self.root = base.appendingPathComponent("Media", isDirectory: true)
        }
        createDirectoriesIfNeeded()
    }

    private func createDirectoriesIfNeeded() {
        for kind in [Kind.audio, .image, .thumbnail, .file] {
            let dir = root.appendingPathComponent(kind.rawValue, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func absoluteURL(for relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    func fileExists(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: absoluteURL(for: relativePath).path)
    }

    /// A fresh relative path like "audio/<uuid>.m4a" (file not yet created).
    func makeRelativePath(kind: Kind, ext: String) -> String {
        let name = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        return "\(kind.rawValue)/\(name)"
    }

    @discardableResult
    func write(_ data: Data, kind: Kind, ext: String) throws -> String {
        let relative = makeRelativePath(kind: kind, ext: ext)
        try data.write(to: absoluteURL(for: relative), options: .atomic)
        return relative
    }

    /// Copies an external file (e.g. picked document) into the sandbox.
    func importFile(from source: URL, preferredExtension: String? = nil) throws -> String {
        let ext = preferredExtension ?? source.pathExtension
        let relative = makeRelativePath(kind: .file, ext: ext)
        let dest = absoluteURL(for: relative)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
        return relative
    }

    func delete(_ relativePath: String) {
        guard !relativePath.isEmpty else { return }
        try? FileManager.default.removeItem(at: absoluteURL(for: relativePath))
    }

    /// Removes all media referenced by a block when it is deleted.
    func deleteMedia(for block: Block) {
        delete(block.imageRelativePath)
        delete(block.thumbnailRelativePath)
        delete(block.audioRelativePath)
        delete(block.fileRelativePath)
    }
}
