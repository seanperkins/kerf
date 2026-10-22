import CADCore
import CAMCore
import Foundation
import PostCore
import Testing
@testable import KerfApp

/// Save All and Save Tiled write a set of files as one: all of them or none, never over an
/// existing file without asking, each replacement an atomic swap, and a failure part way through
/// puts the folder back or says exactly where the old files are.
@Suite struct GCodeFileSetTests {
    private struct Boom: Error {}

    private func file(_ name: String, _ title: String, _ text: String? = "G0 Z1\nM30\n") -> GCodeFileSet.File {
        GCodeFileSet.File(fileName: name, title: title, text: text)
    }

    /// Everything in `dir`, hidden files included.
    private func names(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    private func content(_ dir: URL, _ name: String) throws -> String {
        try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    private func message(_ body: () throws -> Void) -> String {
        do { try body(); return "" } catch { return error.localizedDescription }
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
        try "old".write(to: dir.appendingPathComponent("b.tap"), atomically: true, encoding: .utf8)
        try "keep".write(to: dir.appendingPathComponent("other.tap"), atomically: true, encoding: .utf8)
        let set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B"), file("c.tap", "C")])
        #expect(set.existing(in: dir) == ["b.tap"])
        #expect(set.needsReplaceConfirmation(in: dir))
        // Without the confirmed names the write refuses and the old file stands.
        let refused = message { try set.write(to: dir) }
        #expect(refused.contains("b.tap") && refused.contains("Nothing was saved"))
        #expect(try content(dir, "b.tap") == "old")
        #expect(names(in: dir) == ["b.tap", "other.tap"])
        // With them, the whole set lands, unrelated files stay, and no hidden copy is left behind.
        let urls = try set.write(to: dir, replacing: ["b.tap"])
        #expect(urls.map(\.lastPathComponent) == ["a.tap", "b.tap", "c.tap"])
        #expect(names(in: dir) == ["a.tap", "b.tap", "c.tap", "other.tap"])
        #expect(try content(dir, "b.tap") == "G0 Z1\nM30\n")
        #expect(try content(dir, "other.tap") == "keep")
        #expect(!GCodeFileSet(files: [file("z.tap", "Z")]).needsReplaceConfirmation(in: dir))
    }

    @Test func aDirectoryOrASymlinkAtAPlannedName() throws {
        let dir = AppTestSupport.tempDir()
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("a.tap"), withIntermediateDirectories: false)
        try "inside".write(to: dir.appendingPathComponent("a.tap/x.txt"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: dir.appendingPathComponent("b.tap"), withDestinationURL: dir.appendingPathComponent("nowhere"))
        let set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B")])
        // A directory is never replaced; a dangling link is an existing file to ask about.
        #expect(set.directories(in: dir) == ["a.tap"])
        #expect(set.existing(in: dir) == ["b.tap"])
        let m = message { try set.write(to: dir, replacing: ["b.tap"]) }
        #expect(m.contains("a.tap") && m.contains("Nothing was saved"))
        #expect(try content(dir, "a.tap/x.txt") == "inside")
        let links = GCodeFileSet(files: [file("b.tap", "B")])
        try links.write(to: dir, replacing: ["b.tap"])
        #expect(try content(dir, "b.tap") == "G0 Z1\nM30\n")
    }

    @Test func aFailureOnTheFirstFileLeavesTheFolderAsItWas() throws {
        let dir = AppTestSupport.tempDir()
        try "old a".write(to: dir.appendingPathComponent("a.tap"), atomically: true, encoding: .utf8)
        try "old b".write(to: dir.appendingPathComponent("b.tap"), atomically: true, encoding: .utf8)
        var set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B"), file("c.tap", "C")])
        let live = GCodeFileSet.FileOperations.live
        set.operations.replaceItem = { target, new, backup in
            if target.lastPathComponent == "a.tap" { throw Boom() }
            try live.replaceItem(target, new, backup)
        }
        let m = message { try set.write(to: dir, replacing: ["a.tap", "b.tap"]) }
        #expect(m.contains("a.tap") && m.contains("as they were"))
        #expect(names(in: dir) == ["a.tap", "b.tap"])
        #expect(try content(dir, "a.tap") == "old a")
        #expect(try content(dir, "b.tap") == "old b")
    }

    @Test func aFailurePartWayThroughPutsTheFolderBack() throws {
        // Two files already there; the third swap fails after both were replaced. The old files come
        // back, the new ones go, and nothing hidden is left.
        let dir = AppTestSupport.tempDir()
        try "old a".write(to: dir.appendingPathComponent("a.tap"), atomically: true, encoding: .utf8)
        try "old b".write(to: dir.appendingPathComponent("b.tap"), atomically: true, encoding: .utf8)
        var set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B"), file("c.tap", "C"), file("d.tap", "D")])
        let live = GCodeFileSet.FileOperations.live
        var swapped: [String] = []
        set.operations.replaceItem = { target, new, backup in
            if target.lastPathComponent == "c.tap" { throw Boom() }
            try live.replaceItem(target, new, backup)
            swapped.append(target.lastPathComponent)
        }
        let m = message { try set.write(to: dir, replacing: ["a.tap", "b.tap"]) }
        #expect(m.contains("c.tap") && m.contains("as they were"))
        #expect(swapped == ["a.tap", "b.tap", "b.tap", "a.tap"])   // two in, then restored last first
        #expect(names(in: dir) == ["a.tap", "b.tap"])
        #expect(try content(dir, "a.tap") == "old a")
        #expect(try content(dir, "b.tap") == "old b")
    }

    @Test func aFailedRestoreKeepsTheOldFileAndSaysWhere() throws {
        // The third swap fails and the second file cannot be put back: its kept copy must survive
        // under a hidden name the error spells out, and the error must not claim the folder is as it was.
        let dir = AppTestSupport.tempDir()
        try "old a".write(to: dir.appendingPathComponent("a.tap"), atomically: true, encoding: .utf8)
        try "old b".write(to: dir.appendingPathComponent("b.tap"), atomically: true, encoding: .utf8)
        var set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B"), file("c.tap", "C")])
        let live = GCodeFileSet.FileOperations.live
        set.operations.replaceItem = { target, new, backup in
            if target.lastPathComponent == "c.tap" { throw Boom() }
            if target.lastPathComponent == "b.tap", backup == nil { throw Boom() }   // the restore of b
            try live.replaceItem(target, new, backup)
        }
        let m = message { try set.write(to: dir, replacing: ["a.tap", "b.tap"]) }
        #expect(!m.contains("as they were"))
        #expect(m.contains("kerf-replaced") && m.contains(dir.path))
        let kept = names(in: dir).filter { $0.contains("kerf-replaced") }
        #expect(kept.count == 1 && kept[0].hasPrefix(".b.tap"))
        #expect(try content(dir, "a.tap") == "old a")
        #expect(try content(dir, kept[0]) == "old b")
        #expect(!names(in: dir).contains("c.tap"))
    }

    @Test func aFileThatAppearsAfterTheQuestionStopsTheSave() throws {
        let dir = AppTestSupport.tempDir()
        let set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B")])
        #expect(!set.needsReplaceConfirmation(in: dir))
        try "late".write(to: dir.appendingPathComponent("b.tap"), atomically: true, encoding: .utf8)
        let m = message { try set.write(to: dir, replacing: []) }
        #expect(m.contains("b.tap") && m.contains("Nothing was saved"))
        #expect(names(in: dir) == ["b.tap"])
        #expect(try content(dir, "b.tap") == "late")
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
        #expect(names(in: dir).count == tiles.count)   // no hidden working folder left behind
        // One tile that failed to post keeps the whole set out of the folder.
        tiles[1].result.text = nil
        tiles[1].result.errorMessage = "post failed"
        let broken = GCodeFileSet(tiles: tiles)
        let other = AppTestSupport.tempDir()
        #expect(throws: GCodeFileSetError.self) { try broken.write(to: other) }
        #expect(names(in: other).isEmpty)
        #expect(broken.unposted == [tiles[1].title])
    }

    @Test func aPostProfileExtensionCannotCarryAPath() {
        var profile = BuiltInPosts.avidMach4Inch
        profile.fileExtension = "x/../../evil"
        let name = GCodeExporter.suggestedFileName(jobName: ".", operationName: nil, profile: profile)
        #expect(!name.contains("/"))
        #expect((name as NSString).lastPathComponent == name)
    }
}
