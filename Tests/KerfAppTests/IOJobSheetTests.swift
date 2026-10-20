import AppKit
import CADCore
import CAMCore
import Foundation
import PostCore
import Testing
@testable import KerfApp

@Suite struct IOJobSheetTests {
    func calculatedDocument() -> KerfDocument {
        var p = AppTestSupport.project()
        p.document.name = "Sign <A&B>"
        let ids = p.document.shapes.map(\.id)
        let profile = OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: ids)!
        p.operations = [profile]
        let doc = KerfDocument(project: p, toolLibrary: AppTestSupport.library())
        doc.calculateNow([profile.id])
        return doc
    }

    @Test func sheetListsMaterialToolsAndToolpaths() throws {
        let doc = calculatedDocument()
        let sheet = doc.makeJobSheet(notes: "Clamp corners")
        #expect(sheet.toolpaths.count == 1)
        #expect(sheet.toolpaths[0].time != nil)
        #expect(sheet.toolpaths[0].maxDepth != nil)
        #expect(sheet.tools.count == 1)
        #expect(sheet.material == "24 in × 18 in")
        #expect(sheet.warnings.isEmpty)
        let html = sheet.html(previewPNG: Data([1, 2, 3]))
        #expect(html.contains("Sign &lt;A&amp;B&gt;"))
        #expect(html.contains("data:image/png;base64,AQID"))
        #expect(html.contains("Clamp corners"))
        #expect(html.contains("T\(sheet.tools[0].number)"))
        #expect(html.contains("Material surface"))
    }

    @Test func uncalculatedToolpathIsWarned() {
        var p = AppTestSupport.project()
        let op = OperationFactory.make(kind: .pocket, project: p, library: .seeded, shapeIDs: [p.document.shapes[0].id])!
        p.operations = [op]
        let doc = KerfDocument(project: p, toolLibrary: AppTestSupport.library())
        let sheet = doc.makeJobSheet()
        #expect(sheet.warnings.count == 1)
        #expect(sheet.toolpaths[0].time == nil)
        #expect(sheet.html(previewPNG: nil).contains("No calculated toolpaths"))
    }

    @Test func snapshotIsNotBlank() throws {
        let doc = calculatedDocument()
        let img = try #require(DesignSnapshot.cgImage(document: doc.document, toolpaths: doc.calculatedToolpaths,
                                                      size: CGSize(width: 300, height: 200)))
        let rep = NSBitmapImageRep(cgImage: img)
        var colours = Set<String>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 7) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 7) {
                if let c = rep.colorAt(x: x, y: y) { colours.insert(c.description) }
            }
        }
        #expect(colours.count > 3)
        #expect(doc.jobSheetHTML().contains("data:image/png;base64,"))
    }
}
