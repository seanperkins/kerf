import Foundation
import PostCore

/// A set of G-code programs that belong together (a job split into files, a sheet split into tiles)
/// and are saved as one: every file lands in the folder, or none does. A missing tile is the kind
/// of hole an operator does not notice until the sheet is cut, so a set with a program that failed
/// to post is not written at all, a file already in the folder is replaced only after the caller
/// has asked, and a failure part way through puts back what was there.
struct GCodeFileSet {
    struct File: Equatable {
        var fileName: String
        /// What the file holds, for messages ("Tile 3", "Pocket 1").
        var title: String
        /// The program; nil when its post failed.
        var text: String?
    }

    var files: [File]

    init(files: [File]) { self.files = files }

    /// The planned files of a Save All, in order.
    init(posted: [(file: PlannedGCodeFile, result: GCodeExportResult)]) {
        files = posted.map { File(fileName: $0.file.fileName, title: $0.file.title, text: $0.result.text) }
    }

    /// The tiles of a tiled export, in order.
    init(tiles: [TiledExport.File]) {
        files = tiles.map { File(fileName: $0.fileName, title: $0.title, text: $0.result.text) }
    }

    /// Titles of the files that have no program. While there are any, nothing is written.
    var unposted: [String] { files.filter { $0.text == nil }.map(\.title) }

    /// Names of planned files already in `directory`; the caller asks before they are replaced.
    func existing(in directory: URL) -> [String] {
        files.map(\.fileName).filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    /// True when writing into `directory` would replace a file that is there now.
    func needsReplaceConfirmation(in directory: URL) -> Bool { !existing(in: directory).isEmpty }

    /// Writes every file into `directory` or none: refuses while any post failed; writes the set into
    /// a temporary folder on the same volume, moves the files that are there now aside, moves the new
    /// set into place, and on any failure puts the old files back, removes what this run wrote and
    /// names the file that failed. Returns the written URLs in order.
    @discardableResult
    func write(to directory: URL) throws -> [URL] {
        let missing = unposted
        guard missing.isEmpty else { throw GCodeFileSetError.notPosted(missing) }
        let fm = FileManager.default
        let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: directory, create: true)
        defer { try? fm.removeItem(at: staging) }
        let backups = staging.appendingPathComponent("replaced", isDirectory: true)
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)

        // 1. Every program into the staging folder: nothing in `directory` has changed yet.
        var staged: [(file: File, url: URL)] = []
        for file in files {
            let url = staging.appendingPathComponent(file.fileName)
            do { try file.text!.write(to: url, atomically: true, encoding: .utf8) }
            catch { throw GCodeFileSetError.writeFailed(file: file.fileName, title: file.title, underlying: error) }
            staged.append((file, url))
        }

        // 2. Into place, one at a time, remembering enough to undo.
        var placed: [URL] = []
        var movedAside: [(target: URL, backup: URL)] = []
        func undo() {
            for url in placed { try? fm.removeItem(at: url) }
            for (target, backup) in movedAside.reversed() { try? fm.moveItem(at: backup, to: target) }
        }
        for (file, url) in staged {
            let target = directory.appendingPathComponent(file.fileName)
            do {
                if fm.fileExists(atPath: target.path) {
                    let backup = backups.appendingPathComponent(file.fileName)
                    try fm.moveItem(at: target, to: backup)
                    movedAside.append((target, backup))
                }
                try fm.moveItem(at: url, to: target)
                placed.append(target)
            } catch {
                undo()
                throw GCodeFileSetError.writeFailed(file: file.fileName, title: file.title, underlying: error)
            }
        }
        return placed
    }
}

enum GCodeFileSetError: LocalizedError {
    /// Programs that could not be generated, by title; nothing was written.
    case notPosted([String])
    /// A file could not be written or moved into place; nothing this run wrote remains.
    case writeFailed(file: String, title: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notPosted(let titles):
            let list = titles.joined(separator: ", ")
            return "\(titles.count) program\(titles.count == 1 ? "" : "s") could not be generated (\(list)). "
                + "Nothing was saved: a set with a file missing would cut the job with a piece left out."
        case .writeFailed(let file, let title, let underlying):
            return "Could not write \(file) (\(title)): \(underlying.localizedDescription) "
                + "Nothing from this save was kept, and the files that were in the folder are as they were."
        }
    }
}
