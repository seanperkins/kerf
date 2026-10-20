import AppKit
import CADCore
import CAMCore
import Foundation
import SwiftUI
import Testing
@testable import KerfApp

@Suite @MainActor struct IOClipartTests {
    static let twoSquares = """
    <svg xmlns="http://www.w3.org/2000/svg" width="2in" height="1in" viewBox="0 0 200 100">
      <rect x="0" y="0" width="80" height="80"/><rect x="100" y="0" width="80" height="80"/>
    </svg>
    """

    static func library() throws -> URL {
        let dir = AppTestSupport.tempDir()
        try Data(twoSquares.utf8).write(to: dir.appendingPathComponent("Squares.svg"))
        let sub = dir.appendingPathComponent("Signs/Arrows", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data(twoSquares.utf8).write(to: sub.appendingPathComponent("Left Arrow.svg"))
        try Data("ignore me".utf8).write(to: dir.appendingPathComponent("readme.txt"))
        try Data("x".utf8).write(to: dir.appendingPathComponent(".hidden.svg"))
        try Data(IOModelPartsTests.twoBoards()).write(to: dir.appendingPathComponent("shelf.obj"))
        var p = AppTestSupport.project()
        p.document.layers[0].name = "Outline"
        try p.encoded().write(to: dir.appendingPathComponent("Badge.kerf"))
        return dir
    }

    @Test func scanFindsClipartWithCategories() throws {
        let items = ClipartLibrary.scan(try Self.library())
        #expect(items.map(\.name) == ["Badge", "shelf", "Squares", "Left Arrow"])
        #expect(items.map(\.kind) == [.project, .model, .vector, .vector])
        #expect(items[3].category == "Signs/Arrows")
        #expect(ClipartLibrary.filter(items, query: "arrow").map(\.name) == ["Left Arrow"])
        #expect(ClipartLibrary.filter(items, query: "signs left").count == 1)
        #expect(ClipartLibrary.filter(items, query: "").count == 4)
    }

    @Test func vectorClipartIsCentredAndGrouped() throws {
        let items = ClipartLibrary.scan(try Self.library())
        var p = KerfProject()
        let ids = try ClipartLibrary.insert(items.first { $0.name == "Squares" }!, into: &p)
        #expect(ids.count == 2)
        let shapes = p.document.shapes(ids: ids)
        #expect(Set(shapes.compactMap(\.groupID)).count == 1)
        let b = shapes.reduce(Rect2.empty) { $0.union($1.bounds()) }
        let c = p.document.job.materialBounds.center
        #expect(abs(b.center.x - c.x) < 1e-6 && abs(b.center.y - c.y) < 1e-6)
        #expect(abs(b.width - 1.8) < 1e-6)   // inches, from the SVG's physical size
    }

    @Test func projectClipartBringsItsLayers() throws {
        let items = ClipartLibrary.scan(try Self.library())
        var p = KerfProject()
        let ids = try ClipartLibrary.insert(items.first { $0.kind == .project }!, into: &p)
        #expect(ids.count == 2)
        let layer = try #require(p.document.layers.first { $0.name == "Outline" })
        #expect(p.document.shapes(ids: ids).allSatisfy { $0.layerID == layer.id })
    }

    @Test func modelClipartQueuesThePlacementDialog() throws {
        let items = ClipartLibrary.scan(try Self.library())
        let doc = KerfDocument(project: AppTestSupport.project(), toolLibrary: AppTestSupport.library())
        #expect(doc.insertClipart(items.first { $0.kind == .model }!) == nil)
        #expect(doc.pendingPlacements.count == 1)
        let bad = ClipartLibrary.Item(url: URL(fileURLWithPath: "/nonexistent/x.svg"), name: "x", category: "", kind: .vector)
        #expect(doc.insertClipart(bad) != nil)
    }

    @Test func thumbnailsDrawVectorsAndModels() throws {
        let items = ClipartLibrary.scan(try Self.library())
        for i in items { #expect(ClipartLibrary.thumbnail(of: i) != nil, "\(i.name)") }
    }

    @Test func foldersAreRemembered() throws {
        let suite = "kerf-clipart-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let lib = ClipartLibrary(defaults: defaults)
        #expect(lib.folders == [ClipartLibrary.defaultFolder])
        let extra = URL(fileURLWithPath: "/tmp/my-clipart", isDirectory: true)
        lib.addFolder(extra)
        lib.addFolder(extra)
        #expect(lib.folders.count == 2)
        lib.removeFolder(extra)
        #expect(lib.folders == [ClipartLibrary.defaultFolder])
    }

    @Test func browserRenders() throws {
        let doc = KerfDocument(project: AppTestSupport.project(), toolLibrary: AppTestSupport.library())
        let host = NSHostingView(rootView: ClipartBrowserSheet(document: doc))
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 520)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide > 0)
    }
}
