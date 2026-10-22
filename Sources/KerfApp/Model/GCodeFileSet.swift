import Foundation
import PostCore

/// A set of G-code programs that belong together (a job split into files, a sheet split into tiles)
/// and are saved as one: every file lands in the folder, or none does. A missing tile is the kind
/// of hole an operator does not notice until the sheet is cut, so a set with a program that failed
/// to post is not written at all, a file already in the folder is replaced only after the caller
/// has asked, the files that were there are kept in a hidden folder until the whole set is in, and
/// a failure part way through puts back what was there or says exactly where it is.
struct GCodeFileSet {
    struct File {
        var fileName: String
        /// What the file holds, for messages ("Tile 3", "Pocket 1").
        var title: String
        /// The program; nil when its post failed.
        var text: String?
    }

    /// The file operations a write uses. Tests swap in ones that fail on cue, so every rollback
    /// path is exercised; the app uses `FileManager`. `moveItem` is a rename: it never writes over
    /// an item that is already at the destination.
    struct FileOperations {
        var createDirectory: (URL) throws -> Void
        var writeText: (String, URL) throws -> Void
        var moveItem: (URL, URL) throws -> Void
        var removeItem: (URL) throws -> Void

        static let live = FileOperations(
            createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: false) },
            writeText: { try $0.write(to: $1, atomically: false, encoding: .utf8) },
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

    /// The key under which the file system (APFS folds case and Unicode form) files a name.
    static func collisionKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil)
    }

    /// Names the folder cannot take as one file each: empty, "." or "..", a path rather than a name,
    /// a NUL, or a name another file in the set shares once the file system folds case and Unicode
    /// form, which would make two programs one file. Nothing is written while there are any.
    var invalidNames: [String] {
        var seen: [String: Int] = [:]
        for f in files { seen[Self.collisionKey(f.fileName), default: 0] += 1 }
        return files.map(\.fileName).filter { name in
            name.isEmpty || name == "." || name == ".." || name.contains("/") || name.contains("\0")
                || seen[Self.collisionKey(name), default: 0] > 1
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

    /// Planned names that are symbolic links in `directory`: the link itself is replaced by a file,
    /// and what it pointed to is left as it is, which the caller should say.
    func links(in directory: URL) -> [String] {
        files.map(\.fileName).filter { Self.type(at: directory.appendingPathComponent($0)) == .typeSymbolicLink }
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

    /// Name of the hidden working folder a write makes inside the chosen folder.
    static let workingFolderPrefix = ".kerf-save-"

    /// Writes every file into `directory` or none. Refuses while any post failed, any name is not a
    /// plain unique file name, a planned name is a directory, or a file is there that the caller did
    /// not confirm (`confirmed`: the names shown to the user). Then every program is written into a
    /// hidden working folder inside `directory` (same volume, and nothing visible has changed), and
    /// each file goes into place by two renames: the file that was there into `was/` inside the
    /// working folder, then the new one onto its name. A rename never writes over anything, so a
    /// file that appeared in the meantime stops the save rather than being lost. A failure renames
    /// the files that were there back and removes the new ones, in reverse; if even that fails the
    /// working folder is kept and the error says that the earlier files are in it. On success the
    /// working folder, old files included, is removed. A crash part way through leaves the working
    /// folder in the user's folder, not in a temporary one. Returns the written URLs in order.
    @discardableResult
    func write(to directory: URL, replacing confirmed: [String] = []) throws -> [URL] {
        let missing = unposted
        guard missing.isEmpty else { throw GCodeFileSetError.notPosted(missing) }
        let bad = invalidNames
        guard bad.isEmpty else { throw GCodeFileSetError.invalidNames(bad) }
        let inTheWay = directories(in: directory)
        guard inTheWay.isEmpty else { throw GCodeFileSetError.directoryInTheWay(inTheWay) }
        let present = Set(existing(in: directory))
        let unconfirmed = present.subtracting(confirmed).sorted()
        guard unconfirmed.isEmpty else { throw GCodeFileSetError.notConfirmed(unconfirmed) }

        let tag = String(UUID().uuidString.prefix(8)).lowercased()
        let staging = directory.appendingPathComponent(Self.workingFolderPrefix + tag, isDirectory: true)
        let was = staging.appendingPathComponent("was", isDirectory: true)
        do {
            try operations.createDirectory(staging)
            try operations.createDirectory(was)
        } catch {
            try? operations.removeItem(staging)
            throw GCodeFileSetError.couldNotStage(error)
        }
        var keepWorkingFolder = false
        defer { if !keepWorkingFolder { try? operations.removeItem(staging) } }

        // 1. Every program into the working folder: nothing the user can see has changed.
        for file in files {
            do { try operations.writeText(file.text!, staging.appendingPathComponent(file.fileName)) }
            catch { throw GCodeFileSetError.writeFailed(file: file.fileName, title: file.title, underlying: error) }
        }
        // The folder is the file system's own word on which names it tells apart.
        let stagedCount = (try? FileManager.default.contentsOfDirectory(atPath: staging.path))?.filter { $0 != "was" }.count ?? files.count
        guard stagedCount == files.count else { throw GCodeFileSetError.invalidNames(files.map(\.fileName)) }

        // 2. Into place by renames, each step recorded before it is taken.
        enum Step { case none, movedAside, placed }
        var done: [(file: File, hadOriginal: Bool, step: Step)] = []
        for file in files {
            let target = directory.appendingPathComponent(file.fileName)
            let hadOriginal = present.contains(file.fileName)
            done.append((file, hadOriginal, .none))
            do {
                if hadOriginal {
                    try operations.moveItem(target, was.appendingPathComponent(file.fileName))
                    done[done.count - 1].step = .movedAside
                }
                try operations.moveItem(staging.appendingPathComponent(file.fileName), target)
                done[done.count - 1].step = .placed
            } catch {
                var newLeft: [String] = [], oldLeft: [String] = []
                for entry in done.reversed() {
                    let target = directory.appendingPathComponent(entry.file.fileName)
                    if entry.step == .placed {
                        do { try operations.removeItem(target) } catch { newLeft.append(entry.file.fileName); continue }
                    }
                    if entry.hadOriginal, entry.step != .none {
                        do { try operations.moveItem(was.appendingPathComponent(entry.file.fileName), target) }
                        catch { oldLeft.append(entry.file.fileName) }
                    }
                }
                if newLeft.isEmpty && oldLeft.isEmpty {
                    throw GCodeFileSetError.writeFailed(file: file.fileName, title: file.title, underlying: error)
                }
                keepWorkingFolder = !oldLeft.isEmpty
                throw GCodeFileSetError.rollbackFailed(file: file.fileName, underlying: error, newLeft: newLeft,
                                                       oldLeft: oldLeft, workingFolder: was)
            }
        }
        // 3. The set is in place: the working folder, old files included, goes with the defer.
        return done.map { directory.appendingPathComponent($0.file.fileName) }
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
    /// A file could not be written or put in place; the folder is as it was.
    case writeFailed(file: String, title: String, underlying: Error)
    /// A file could not be put in place and the folder could not be put back: `newLeft` are files
    /// from this save still in the folder, `oldLeft` are earlier files still in `workingFolder`.
    case rollbackFailed(file: String, underlying: Error, newLeft: [String], oldLeft: [String], workingFolder: URL)

    var errorDescription: String? {
        func list(_ names: [String]) -> String { names.joined(separator: ", ") }
        func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        switch self {
        case .notPosted(let titles):
            return "\(count(titles.count, "program")) could not be generated (\(list(titles))). "
                + "Nothing was saved: a set with a file missing would cut the job with a piece left out."
        case .invalidNames(let names):
            return "\(count(names.count, "file name")) cannot be used in one folder (\(list(names))). Nothing was saved."
        case .directoryInTheWay(let names):
            return "The folder has a folder, not a file, named \(list(names)). Kerf does not replace folders. Nothing was saved."
        case .notConfirmed(let names):
            return "\(count(names.count, "file")) appeared in the folder after you were asked (\(list(names))). Nothing was saved; save again to be asked about \(names.count == 1 ? "it" : "them")."
        case .couldNotStage(let error):
            return "Could not make a working folder beside the files: \(error.localizedDescription) Nothing was saved."
        case .writeFailed(let file, let title, let underlying):
            return "Could not write \(file) (\(title)): \(underlying.localizedDescription) "
                + "Nothing from this save was kept, and the files that were in the folder are as they were."
        case .rollbackFailed(let file, let underlying, let newLeft, let oldLeft, let workingFolder):
            var parts = ["Could not write \(file): \(underlying.localizedDescription) Putting the folder back failed too."]
            if !newLeft.isEmpty {
                parts.append("\(count(newLeft.count, "file")) from this save \(newLeft.count == 1 ? "is" : "are") still in the folder (\(list(newLeft))); do not run \(newLeft.count == 1 ? "it" : "them") as a set.")
            }
            if !oldLeft.isEmpty {
                parts.append("Your earlier \(count(oldLeft.count, "file")) (\(list(oldLeft))) \(oldLeft.count == 1 ? "is" : "are") in \(workingFolder.path); move \(oldLeft.count == 1 ? "it" : "them") back by hand.")
            }
            return parts.joined(separator: " ")
        }
    }
}
