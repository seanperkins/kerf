import CADCore
import CAMCore
import Foundation
import PostCore
import Testing
@testable import KerfApp

/// Save All and Save Tiled write a set of files as one: all of them or none, never over an
/// existing file without asking, and a failure part way through puts the folder back or says
/// exactly where the old files are.
@Suite struct GCodeFileSetTests {
    private struct Boom: Error {}

    private func file(_ name: String, _ title: String, _ text: String? = "G0 Z1\nM30\n") -> GCodeFileSet.File {
        GCodeFileSet.File(fileName: name, title: title, text: text)
    }

    /// Everything in `dir`, hidden items included.
    private func names(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    private func content(_ dir: URL, _ name: String) throws -> String {
        try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    private func message(_ body: () throws -> Void) -> String {
        do { try body(); return "" } catch { return error.localizedDescription }
    }

    private func write(_ text: String, _ dir: URL, _ name: String) throws {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @Test func aSetWithAFailedPostWritesNothingAndNamesTheFile() {
        let dir = AppTestSupport.tempDir()
        let set = GCodeFileSet(files: [file("tile_1.tap", "Tile 1"), file("tile_2.tap", "Tile 2", nil), file("tile_3.tap", "Tile 3")])
        #expect(set.unposted == ["Tile 2"])
        let m = message { try set.write(to: dir) }
        #expect(m.contains("Tile 2") && m.contains("Nothing was saved"))
        #expect(names(in: dir).isEmpty)
    }

    @Test func namesThatAreNotOnePlainFileEachAreRefused() {
        let dir = AppTestSupport.tempDir()
        for bad in ["", ".", "..", "a/b.tap", "x/../../evil.tap", "nul\0.tap"] {
            let set = GCodeFileSet(files: [file(bad, "Bad"), file("ok.tap", "OK")])
            #expect(set.invalidNames == [bad], "\(bad.debugDescription)")
            #expect(throws: GCodeFileSetError.self) { try set.write(to: dir) }
        }
        // Two names the file system would fold into one (case, Unicode form) would make two programs one file.
        let twins = GCodeFileSet(files: [file("Caf\u{E9}.tap", "A"), file("Cafe\u{301}.tap", "B"), file("cafe\u{301}.tap", "C")])
        #expect(twins.invalidNames.count == 3)
        #expect(throws: GCodeFileSetError.self) { try twins.write(to: dir) }
        #expect(names(in: dir).isEmpty)
    }

    @Test func existingFilesAreReportedAndNotTouchedWithoutConfirmation() throws {
        let dir = AppTestSupport.tempDir()
        try write("old", dir, "b.tap")
        try write("keep", dir, "other.tap")
        let set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B"), file("c.tap", "C")])
        #expect(set.existing(in: dir) == ["b.tap"])
        #expect(set.needsReplaceConfirmation(in: dir))
        // Without the confirmed names the write refuses and the old file stands.
        let refused = message { try set.write(to: dir) }
        #expect(refused.contains("b.tap") && refused.contains("Nothing was saved"))
        #expect(try content(dir, "b.tap") == "old")
        #expect(names(in: dir) == ["b.tap", "other.tap"])
        // With them, the whole set lands, unrelated files stay, and the working folder is gone.
        let urls = try set.write(to: dir, replacing: ["b.tap"])
        #expect(urls.map(\.lastPathComponent) == ["a.tap", "b.tap", "c.tap"])
        #expect(names(in: dir) == ["a.tap", "b.tap", "c.tap", "other.tap"])
        #expect(try content(dir, "b.tap") == "G0 Z1\nM30\n")
        #expect(try content(dir, "other.tap") == "keep")
        #expect(!GCodeFileSet(files: [file("z.tap", "Z")]).needsReplaceConfirmation(in: dir))
    }

    @Test func aDirectoryIsNeverReplacedAndALinkIsReplacedAsALink() throws {
        let dir = AppTestSupport.tempDir()
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("a.tap"), withIntermediateDirectories: false)
        try write("inside", dir, "a.tap/x.txt")
        try fm.createSymbolicLink(at: dir.appendingPathComponent("b.tap"), withDestinationURL: dir.appendingPathComponent("nowhere"))
        let elsewhere = AppTestSupport.tempDir()
        try write("pointed at", elsewhere, "real.tap")
        try fm.createSymbolicLink(at: dir.appendingPathComponent("c.tap"), withDestinationURL: elsewhere.appendingPathComponent("real.tap"))
        let set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B"), file("c.tap", "C")])
        // A directory stops the save before anything changes; links, dangling or live, are asked about.
        #expect(set.directories(in: dir) == ["a.tap"])
        #expect(set.existing(in: dir) == ["b.tap", "c.tap"])
        #expect(set.links(in: dir) == ["b.tap", "c.tap"])
        let m = message { try set.write(to: dir, replacing: ["b.tap", "c.tap"]) }
        #expect(m.contains("a.tap") && m.contains("Nothing was saved"))
        #expect(try content(dir, "a.tap/x.txt") == "inside")
        // Confirmed links are replaced by files; what a live link pointed to is untouched.
        let links = GCodeFileSet(files: [file("b.tap", "B"), file("c.tap", "C")])
        try links.write(to: dir, replacing: ["b.tap", "c.tap"])
        #expect(try content(dir, "b.tap") == "G0 Z1\nM30\n")
        #expect(try content(dir, "c.tap") == "G0 Z1\nM30\n")
        #expect(try fm.attributesOfItem(atPath: dir.appendingPathComponent("c.tap").path)[.type] as? FileAttributeType == .typeRegular)
        #expect(try content(elsewhere, "real.tap") == "pointed at")
        #expect(names(in: dir) == ["a.tap", "b.tap", "c.tap"])
        let r = ReplaceRequest(set: links, directory: dir)
        #expect(r.links.isEmpty)   // they are files now
    }

    @Test func aFailureBeforeAnythingMovedLeavesTheFolderAsItWas() throws {
        // Writing the third program into the working folder fails: nothing visible or hidden remains.
        let dir = AppTestSupport.tempDir()
        try write("old a", dir, "a.tap")
        var set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B"), file("c.tap", "C")])
        let live = GCodeFileSet.FileOperations.live
        set.operations.writeText = { text, url in
            if url.lastPathComponent == "c.tap" { throw Boom() }
            try live.writeText(text, url)
        }
        let m = message { try set.write(to: dir, replacing: ["a.tap"]) }
        #expect(m.contains("c.tap") && m.contains("as they were"))
        #expect(names(in: dir) == ["a.tap"])
        #expect(try content(dir, "a.tap") == "old a")
        // And when the working folder itself cannot be made.
        var noStage = set
        noStage.operations.createDirectory = { _ in throw Boom() }
        #expect(message { try noStage.write(to: dir, replacing: ["a.tap"]) }.contains("Nothing was saved"))
        #expect(names(in: dir) == ["a.tap"])
    }

    @Test func aFailurePartWayThroughPutsTheFolderBack() throws {
        // Two files already there; the third cannot be put in place after both were replaced. The old
        // files come back, the new ones go, and nothing hidden is left.
        let dir = AppTestSupport.tempDir()
        try write("old a", dir, "a.tap")
        try write("old b", dir, "b.tap")
        var set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B"), file("c.tap", "C"), file("d.tap", "D")])
        let live = GCodeFileSet.FileOperations.live
        var moves: [String] = []
        set.operations.moveItem = { from, to in
            if to.lastPathComponent == "c.tap" { throw Boom() }
            try live.moveItem(from, to)
            moves.append("\(from.lastPathComponent)>\(to.lastPathComponent)")
        }
        let m = message { try set.write(to: dir, replacing: ["a.tap", "b.tap"]) }
        #expect(m.contains("c.tap") && m.contains("as they were"))
        // a aside, a in, b aside, b in; then b back, a back (the new ones are removed, not moved).
        #expect(moves == ["a.tap>a.tap", "a.tap>a.tap", "b.tap>b.tap", "b.tap>b.tap", "b.tap>b.tap", "a.tap>a.tap"])
        #expect(names(in: dir) == ["a.tap", "b.tap"])
        #expect(try content(dir, "a.tap") == "old a")
        #expect(try content(dir, "b.tap") == "old b")
    }

    @Test func aFailureBetweenMovingAsideAndPuttingInPlaceRestoresThatFile() throws {
        // The old b has been renamed aside when the new b cannot go in: b must come back too, and a
        // dangling link at a name is renamed aside and back the same way.
        let dir = AppTestSupport.tempDir()
        try write("old a", dir, "a.tap")
        try write("old b", dir, "b.tap")
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("l.tap"), withDestinationURL: dir.appendingPathComponent("nowhere"))
        for failing in ["b.tap", "l.tap"] {
            var set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B"), file("l.tap", "L")])
            let live = GCodeFileSet.FileOperations.live
            set.operations.moveItem = { from, to in
                // The second rename only: the staged file (not the restore out of was/) onto its name.
                if to.lastPathComponent == failing, from.deletingLastPathComponent().lastPathComponent.hasPrefix(GCodeFileSet.workingFolderPrefix) { throw Boom() }
                try live.moveItem(from, to)
            }
            let m = message { try set.write(to: dir, replacing: ["a.tap", "b.tap", "l.tap"]) }
            #expect(m.contains(failing) && m.contains("as they were"), "\(failing): \(m)")
            #expect(names(in: dir) == ["a.tap", "b.tap", "l.tap"], "\(failing)")
            #expect(try content(dir, "a.tap") == "old a")
            #expect(try content(dir, "b.tap") == "old b")
            #expect(try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("l.tap").path)[.type] as? FileAttributeType == .typeSymbolicLink)
        }
    }

    @Test func aFailedRestoreKeepsTheOldFilesAndSaysWhere() throws {
        // The third file cannot go in and the old b cannot come back: it must survive in the working
        // folder the error names, the new a must be gone, and the error must not claim the folder is as it was.
        let dir = AppTestSupport.tempDir()
        try write("old a", dir, "a.tap")
        try write("old b", dir, "b.tap")
        var set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B"), file("c.tap", "C")])
        let live = GCodeFileSet.FileOperations.live
        set.operations.moveItem = { from, to in
            if to.lastPathComponent == "c.tap" { throw Boom() }
            if to.lastPathComponent == "b.tap", from.path.contains("/was/") { throw Boom() }   // the restore of b
            try live.moveItem(from, to)
        }
        let m = message { try set.write(to: dir, replacing: ["a.tap", "b.tap"]) }
        #expect(!m.contains("as they were"))
        #expect(m.contains("earlier 1 file") && m.contains("b.tap") && m.contains("/was"))
        let working = names(in: dir).filter { $0.hasPrefix(GCodeFileSet.workingFolderPrefix) }
        #expect(working.count == 1)
        #expect(try content(dir, "a.tap") == "old a")
        #expect(try content(dir, "\(working[0])/was/b.tap") == "old b")
        #expect(!names(in: dir).contains("c.tap"))
        #expect(m.contains(dir.appendingPathComponent(working[0]).appendingPathComponent("was").path))
    }

    @Test func aNewFileThatCannotBeRemovedIsNamedAsSuch() throws {
        let dir = AppTestSupport.tempDir()
        var set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B")])
        let live = GCodeFileSet.FileOperations.live
        set.operations.moveItem = { from, to in
            if to.lastPathComponent == "b.tap" { throw Boom() }
            try live.moveItem(from, to)
        }
        set.operations.removeItem = { url in
            if url.lastPathComponent == "a.tap" { throw Boom() }
            try live.removeItem(url)
        }
        let m = message { try set.write(to: dir) }
        #expect(m.contains("from this save") && m.contains("a.tap") && !m.contains("earlier"))
        #expect(names(in: dir) == ["a.tap"])   // the working folder goes: nothing of the user's is in it
    }

    @Test func aFileThatAppearsLateStopsTheSave() throws {
        let dir = AppTestSupport.tempDir()
        var set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B")])
        #expect(!set.needsReplaceConfirmation(in: dir))
        // After the question, before the write: refused outright.
        try write("late", dir, "b.tap")
        let m = message { try set.write(to: dir, replacing: []) }
        #expect(m.contains("b.tap") && m.contains("Nothing was saved"))
        #expect(try content(dir, "b.tap") == "late")
        try FileManager.default.removeItem(at: dir.appendingPathComponent("b.tap"))
        // During the write (a sync client drops it in while programs are being staged): a rename never
        // writes over it, so the save fails and rolls back with the late file untouched.
        let live = GCodeFileSet.FileOperations.live
        set.operations.writeText = { text, url in
            try live.writeText(text, url)
            if url.lastPathComponent == "a.tap" { try "late".write(to: dir.appendingPathComponent("b.tap"), atomically: true, encoding: .utf8) }
        }
        let m2 = message { try set.write(to: dir, replacing: []) }
        #expect(m2.contains("b.tap") && m2.contains("as they were"))
        #expect(names(in: dir) == ["b.tap"])
        #expect(try content(dir, "b.tap") == "late")
    }

    @Test func theReplaceRequestSummarisesTheNames() throws {
        let dir = AppTestSupport.tempDir()
        for n in 1...7 { try write("x", dir, "f\(n).tap") }
        let five = ReplaceRequest(set: GCodeFileSet(files: (1...5).map { file("f\($0).tap", "F\($0)") }), directory: dir)
        #expect(five.names.count == 5 && !five.summary.contains("more"))
        let six = ReplaceRequest(set: GCodeFileSet(files: (1...6).map { file("f\($0).tap", "F\($0)") }), directory: dir)
        #expect(six.summary.contains("and 1 more") && six.summary.contains("them"))
        let one = ReplaceRequest(set: GCodeFileSet(files: [file("f7.tap", "F7"), file("new.tap", "N")]), directory: dir)
        #expect(one.names == ["f7.tap"] && one.summary.contains("over it"))
    }

    @Test func tiledSetsComeFromTheTiles() throws {
        // A 110 x 24 in board split into 60 in tiles: a pocket across the seam and a profile at the end.
        var d = Document(name: "Bench", job: JobSetup(width: 110, height: 24, thickness: 0.75))
        let l = d.defaultLayerID
        d.add(AppTestSupport.rect(45, 8, 20, 6, layer: l))
        d.add(AppTestSupport.rect(90, 8, 10, 6, layer: l))
        var p = KerfProject(document: d)
        p.operations = [
            OperationFactory.make(kind: .pocket, project: p, library: .seeded, shapeIDs: [d.shapes[0].id])!,
            OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: [d.shapes[1].id])!,
        ]
        let doc = KerfDocument(project: p, toolLibrary: AppTestSupport.library())
        doc.calculateNow(doc.project.operations.map(\.id))
        var tiles = TiledExport.files(project: doc.project, results: doc.results, profile: BuiltInPosts.avidMach4Inch,
                                      groupByTool: false, settings: TilingSettings(tileWidth: 60, tileHeight: 96))
        #expect(tiles.count >= 2)
        let good = GCodeFileSet(tiles: tiles)
        #expect(good.unposted.isEmpty && good.invalidNames.isEmpty)
        let dir = AppTestSupport.tempDir()
        #expect(try good.write(to: dir).count == tiles.count)
        #expect(names(in: dir).count == tiles.count)   // no working folder left behind
        // One tile that failed to post keeps the whole set out of the folder.
        tiles[1].result.text = nil
        tiles[1].result.errorMessage = "post failed"
        let broken = GCodeFileSet(tiles: tiles)
        let other = AppTestSupport.tempDir()
        #expect(throws: GCodeFileSetError.self) { try broken.write(to: other) }
        #expect(names(in: other).isEmpty)
        #expect(broken.unposted == [tiles[1].title])
        // A post profile's extension is user JSON: it is cleaned for tiles as for Save All.
        var hostile = BuiltInPosts.avidMach4Inch
        hostile.fileExtension = "x/../../evil"
        let tileNames = TiledExport.files(project: doc.project, results: doc.results, profile: hostile,
                                          groupByTool: false, settings: TilingSettings(tileWidth: 60, tileHeight: 96)).map(\.fileName)
        #expect(!tileNames.isEmpty && tileNames.allSatisfy { !$0.contains("/") && $0.hasSuffix(".xevil") })
    }

    @Test func fileNamesAreOnePlainVisibleNameEach() {
        var profile = BuiltInPosts.avidMach4Inch
        profile.fileExtension = "x/../../evil"
        let name = GCodeExporter.suggestedFileName(jobName: ".", operationName: nil, profile: profile)
        #expect(!name.contains("/") && !name.hasPrefix("."))
        profile.fileExtension = ""
        #expect(GCodeExporter.suggestedFileName(jobName: ".hidden", operationName: "Op", profile: profile) == "_hidden_Op.tap")
    }
}
