import Foundation
import PostCore

/// A set of G-code programs that belong together (a job split into files, a sheet split into tiles)
/// and are saved as one: every file lands in the folder, or none does. A missing tile is the kind
/// of hole an operator does not notice until the sheet is cut, so a set with a program that failed
/// to post is not written at all, a file already in the folder is replaced only after the caller
/// has asked, each replacement is an atomic swap that keeps the old file beside the new one until
/// the whole set is in place, and a failure part way through puts back what was there.
struct GCodeFileSet {
    struct File {
        var fileName: String
        /// What the file holds, for messages ("Tile 3", "Pocket 1").
        var title: String
        /// The program; nil when its post failed.
        var text: String?
    }

    /// The file operations a write uses. Tests swap in ones that fail on cue, so the rollback is
    /// exercised; the app uses `FileManager`.
    struct FileOperations {
        var createDirectory: (URL) throws -> Void
        var writeText: (String, URL) throws -> Void
        /// Atomically puts `new` at `target`; with a backup name, the file that was at `target` is
        /// kept under that name in the same folder (nothing is kept when there was none).
        var replaceItem: (_ target: URL, _ new: URL, _ backupName: String?) throws -> Void
        /// Renames an item (used for a symbolic link, which `replaceItem` would follow).
        var moveItem: (URL, URL) throws -> Void
        var removeItem: (URL) throws -> Void

        static let live = FileOperations(
            createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: false) },
            writeText: { try $0.write(to: $1, atomically: true, encoding: .utf8) },
            replaceItem: { target, new, backup in
                _ = try FileManager.default.replaceItemAt(target, withItemAt: new, backupItemName: backup,
                                                          options: backup == nil ? [] : .withoutDeletingBackupItem)
            },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) },
            removeItem: { try FileManager.default.removeItem(at: $0) })
    }

    var files: [File]
    var operations = FileOperations.live

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

    /// Names the folder cannot take as one file each: empty, "." or "..", a path rather than a name,
    /// a NUL, or a name another file in the set shares once the file system folds case and Unicode
    /// form (APFS does both), which would make two programs one file. Nothing is written while any.
    var invalidNames: [String] {
        var seen: [String: Int] = [:]
        for f in files { seen[f.fileName.precomposedStringWithCanonicalMapping.lowercased(), default: 0] += 1 }
        return files.map(\.fileName).filter { name in
            name.isEmpty || name == "." || name == ".." || name.contains("/") || name.contains("\0")
                || (name as NSString).lastPathComponent != name
                || seen[name.precomposedStringWithCanonicalMapping.lowercased(), default: 0] > 1
        }
    }

    /// Names of planned files already in `directory` (a file or a symbolic link, not a directory);
    /// the caller asks before they are replaced.
    func existing(in directory: URL) -> [String] {
        files.map(\.fileName).filter { name in
            if let type = Self.type(at: directory.appendingPathComponent(name)) { return type != .typeDirectory }
            return false
        }
    }

    /// Planned names that are directories in `directory`. A directory is never replaced.
    func directories(in directory: URL) -> [String] {
        files.map(\.fileName).filter { Self.type(at: directory.appendingPathComponent($0)) == .typeDirectory }
    }

    /// True when writing into `directory` would replace a file that is there now.
    func needsReplaceConfirmation(in directory: URL) -> Bool { !existing(in: directory).isEmpty }

    /// What is at `url` without following a final symbolic link; nil when nothing is.
    private static func type(at url: URL) -> FileAttributeType? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
    }

    /// Writes every file into `directory` or none. Refuses while any post failed, any name is not a
    /// plain unique file name, a planned name is a directory, or a file is there that the caller did
    /// not confirm (`confirmed`, the names shown to the user). Then: the whole set is written into a
    /// hidden folder inside `directory` (same volume, nothing in the folder changed yet); each file
    /// is swapped into place atomically, the file that was there kept beside it under a hidden
    /// name; a failure swaps the kept files back and removes the new ones, and if even that fails
    /// the error says which kept files remain and where; on success the kept files are removed.
    /// A crash part way through leaves the hidden kept files in the folder, not in a temporary one.
    /// Returns the written URLs in order.
    @discardableResult
    func write(to directory: URL, replacing confirmed: [String] = []) throws -> [URL] {
        let missing = unposted
        guard missing.isEmpty else { throw GCodeFileSetError.notPosted(missing) }
        let bad = invalidNames
        guard bad.isEmpty else { throw GCodeFileSetError.invalidNames(bad) }
        let inTheWay = directories(in: directory)
        guard inTheWay.isEmpty else { throw GCodeFileSetError.directoryInTheWay(inTheWay) }
        let present = Set(existing(in: directory))
        let links = Set(files.map(\.fileName).filter { Self.type(at: directory.appendingPathComponent($0)) == .typeSymbolicLink })
        let unconfirmed = present.subtracting(confirmed).sorted()
        guard unconfirmed.isEmpty else { throw GCodeFileSetError.notConfirmed(unconfirmed) }

        let tag = String(UUID().uuidString.prefix(8)).lowercased()
        let staging = directory.appendingPathComponent(".kerf-save-\(tag)", isDirectory: true)
        do { try operations.createDirectory(staging) } catch { throw GCodeFileSetError.couldNotStage(error) }
        defer { try? operations.removeItem(staging) }   // never holds an original

        // 1. Every program into the hidden folder: nothing the user can see has changed.
        for file in files {
            do { try operations.writeText(file.text!, staging.appendingPathComponent(file.fileName)) }
            catch { throw GCodeFileSetError.writeFailed(file: file.fileName, title: file.title, underlying: error) }
        }

        // 2. Into place, one atomic swap at a time, the old file kept beside the new one. A symbolic
        //    link is renamed aside first (the swap would follow it) and renamed back on failure.
        var placed: [(target: URL, backup: URL?, link: Bool)] = []
        for file in files {
            let target = directory.appendingPathComponent(file.fileName)
            let backup = present.contains(file.fileName) ? directory.appendingPathComponent(".\(file.fileName).kerf-replaced-\(tag)") : nil
            let link = links.contains(file.fileName)
            do {
                if link, let backup {
                    try operations.moveItem(target, backup)
                    try operations.replaceItem(target, staging.appendingPathComponent(file.fileName), nil)
                } else {
                    try operations.replaceItem(target, staging.appendingPathComponent(file.fileName), backup?.lastPathComponent)
                }
                placed.append((target, backup, link))
            } catch {
                var stranded: [String] = []
                for (done, backup, wasLink) in placed.reversed() {
                    do {
                        if let backup, wasLink {
                            try operations.removeItem(done)
                            try operations.moveItem(backup, done)
                        } else if let backup {
                            try operations.replaceItem(done, backup, nil)
                        } else {
                            try operations.removeItem(done)
                        }
                    } catch {
                        stranded.append((backup ?? done).lastPathComponent)
                    }
                }
                if stranded.isEmpty {
                    throw GCodeFileSetError.writeFailed(file: file.fileName, title: file.title, underlying: error)
                }
                throw GCodeFileSetError.rollbackFailed(file: file.fileName, underlying: error, kept: stranded, directory: directory)
            }
        }

        // 3. The set is in place: the kept copies are no longer needed.
        for (_, backup, _) in placed { if let backup { try? operations.removeItem(backup) } }
        return placed.map(\.target)
    }
}

enum GCodeFileSetError: LocalizedError {
    /// Programs that could not be generated, by title; nothing was written.
    case notPosted([String])
    /// Names the folder cannot take as one file each; nothing was written.
    case invalidNames([String])
    /// Planned names that are directories in the folder; nothing was written.
    case directoryInTheWay([String])
    /// Files in the folder the user was not asked about; nothing was written.
    case notConfirmed([String])
    /// The hidden working folder could not be made; nothing was written.
    case couldNotStage(Error)
    /// A file could not be written or swapped in; the folder is as it was.
    case writeFailed(file: String, title: String, underlying: Error)
    /// A file could not be swapped in and some of the files that were there could not be put back:
    /// they are kept in the folder under the listed hidden names.
    case rollbackFailed(file: String, underlying: Error, kept: [String], directory: URL)

    var errorDescription: String? {
        func list(_ names: [String]) -> String { names.joined(separator: ", ") }
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        switch self {
        case .notPosted(let titles):
            return "\(plural(titles.count, "program")) could not be generated (\(list(titles))). "
                + "Nothing was saved: a set with a file missing would cut the job with a piece left out."
        case .invalidNames(let names):
            return "\(plural(names.count, "file name")) cannot be used in one folder (\(list(names))). Nothing was saved."
        case .directoryInTheWay(let names):
            return "The folder has a folder, not a file, named \(list(names)). Kerf does not replace folders. Nothing was saved."
        case .notConfirmed(let names):
            return "\(plural(names.count, "file")) appeared in the folder after you were asked (\(list(names))). Nothing was saved; save again to be asked about them."
        case .couldNotStage(let error):
            return "Could not make a working folder beside the files: \(error.localizedDescription) Nothing was saved."
        case .writeFailed(let file, let title, let underlying):
            return "Could not write \(file) (\(title)): \(underlying.localizedDescription) "
                + "Nothing from this save was kept, and the files that were in the folder are as they were."
        case .rollbackFailed(let file, let underlying, let kept, let directory):
            return "Could not write \(file): \(underlying.localizedDescription) "
                + "Putting the folder back failed too. Your earlier \(plural(kept.count, "file")) still exist in "
                + "\(directory.path) under the hidden \(kept.count == 1 ? "name" : "names") \(list(kept)); rename them to recover them."
        }
    }
}
