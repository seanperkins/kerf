import CADCore
import CAMCore
import Foundation
import PostCore
import Testing
@testable import KerfApp

/// Save All and Save Tiled write a set of files as one: all of them or none, never over an
/// existing file without asking, and a failure part way through leaves the folder as it was.
@Suite struct GCodeFileSetTests {
    private func file(_ name: String, _ title: String, _ text: String? = "G0 Z1\nM30\n") -> GCodeFileSet.File {
        GCodeFileSet.File(fileName: name, title: title, text: text)
    }

    private func names(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    @Test func aSetWithAFailedPostWritesNothingAndNamesTheFile() {
        let dir = AppTestSupport.tempDir()
        let set = GCodeFileSet(files: [file("tile_1.tap", "Tile 1"), file("tile_2.tap", "Tile 2", nil), file("tile_3.tap", "Tile 3")])
        #expect(set.unposted == ["Tile 2"])
        #expect(throws: GCodeFileSetError.self) { try set.write(to: dir) }
        do { try set.write(to: dir) } catch {
            #expect(error.localizedDescription.contains("Tile 2"))
            #expect(error.localizedDescription.contains("Nothing was saved"))
        }
        #expect(names(in: dir).isEmpty)
    }

    @Test func existingFilesAreReportedAndNotTouchedWithoutConfirmation() throws {
        let dir = AppTestSupport.tempDir()
        try "old".write(to: dir.appendingPathComponent("b.tap"), atomically: true, encoding: .utf8)
        try "keep".write(to: dir.appendingPathComponent("other.tap"), atomically: true, encoding: .utf8)
        let set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B"), file("c.tap", "C")])
        #expect(set.existing(in: dir) == ["b.tap"])
        #expect(set.needsReplaceConfirmation(in: dir))
        // The sheet asks first; until the user agrees nothing is written. Asking is the caller's job,
        // so the model only reports; the file is still the old one.
        #expect(try String(contentsOf: dir.appendingPathComponent("b.tap"), encoding: .utf8) == "old")
        // After the user agrees, the whole set lands and unrelated files stay.
        let urls = try set.write(to: dir)
        #expect(urls.map(\.lastPathComponent) == ["a.tap", "b.tap", "c.tap"])
        #expect(names(in: dir) == ["a.tap", "b.tap", "c.tap", "other.tap"])
        #expect(try String(contentsOf: dir.appendingPathComponent("b.tap"), encoding: .utf8) == "G0 Z1\nM30\n")
        #expect(try String(contentsOf: dir.appendingPathComponent("other.tap"), encoding: .utf8) == "keep")
        #expect(!GCodeFileSet(files: [file("z.tap", "Z")]).needsReplaceConfirmation(in: dir))
    }

    @Test func aFailurePartWayThroughPutsTheFolderBack() throws {
        // Two of three already there; the folder becomes read-only, so the first move fails after the
        // set was staged. Nothing new may remain and the old files must be as they were.
        let dir = AppTestSupport.tempDir()
        try "old a".write(to: dir.appendingPathComponent("a.tap"), atomically: true, encoding: .utf8)
        try "old b".write(to: dir.appendingPathComponent("b.tap"), atomically: true, encoding: .utf8)
        let set = GCodeFileSet(files: [file("a.tap", "A"), file("b.tap", "B"), file("c.tap", "C")])
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        var message = ""
        do { try set.write(to: dir); Issue.record("write into a read-only folder succeeded") } catch { message = error.localizedDescription }
        #expect(message.contains("a.tap"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        #expect(names(in: dir) == ["a.tap", "b.tap"])
        #expect(try String(contentsOf: dir.appendingPathComponent("a.tap"), encoding: .utf8) == "old a")
        #expect(try String(contentsOf: dir.appendingPathComponent("b.tap"), encoding: .utf8) == "old b")
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
        #expect(good.unposted.isEmpty)
        let dir = AppTestSupport.tempDir()
        #expect(try good.write(to: dir).count == tiles.count)
        // One tile that failed to post keeps the whole set out of the folder.
        tiles[1].result.text = nil
        tiles[1].result.errorMessage = "post failed"
        let broken = GCodeFileSet(tiles: tiles)
        let other = AppTestSupport.tempDir()
        #expect(throws: GCodeFileSetError.self) { try broken.write(to: other) }
        #expect(names(in: other).isEmpty)
        #expect(broken.unposted == [tiles[1].title])
    }
}
