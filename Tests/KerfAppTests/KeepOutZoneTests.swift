import CADCore
import CAMCore
import Foundation
import PostCore
import Testing
@testable import KerfApp

@Test func keepOutZonesBlockExportOfToolpathsThatHitThem() throws {
    var project = AppTestSupport.project() // 2x1 rectangles at (1,1) and (5,1)
    let ids = project.document.shapes.map(\.id)
    let op = AnyOperation.profile(ProfileOperation(setup: OperationSetup(name: "Cut", toolID: ToolLibrary.seeded.tools[0].id,
                                                                         shapeIDs: ids)))
    project.upsertOperation(op)
    let ctx = CAMContext(document: project.document, tools: .seeded)
    let tps = try op.generate(in: ctx)
    let profile = BuiltInPosts.avidMach4Inch
    let clean = GCodeExporter.export(project: project, toolpaths: tps, profile: profile, jobName: "T")
    #expect(!clean.issues.contains { $0.message.contains("keep-out") })
    // A clamp over the left end of the first rectangle.
    let clamp = KeepOutEditing.zones(from: [AppTestSupport.rect(0.5, 1.2, 0.8, 0.5, layer: project.document.defaultLayerID)],
                                     height: 1, tolerance: 0.0005, existing: 0)
    #expect(clamp.count == 1 && clamp[0].outline.count == 4)
    project.document.keepOutZones = clamp
    let blocked = GCodeExporter.export(project: project, toolpaths: tps, profile: profile, jobName: "T")
    #expect(blocked.issues.contains { $0.severity == .error && $0.message.contains("keep-out zone") })
}

@Test func keepOutZonesScaleWithDocumentUnits() {
    var doc = Document()
    doc.keepOutZones = [KeepOutZone(name: "C", outline: [Vec2(1, 1), Vec2(2, 1), Vec2(2, 2)], height: 1)]
    let mm = doc.converted(to: .millimeter)
    #expect(mm.keepOutZones?[0].outline[1] == Vec2(50.8, 25.4))
    #expect(mm.keepOutZones?[0].height == 25.4)
}
