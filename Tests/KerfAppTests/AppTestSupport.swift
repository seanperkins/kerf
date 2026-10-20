import CADCore
import CAMCore
import Foundation
@testable import KerfApp

enum AppTestSupport {
    static func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kerf-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func library() -> ToolLibraryModel {
        ToolLibraryModel(store: ToolLibraryStore(fileURL: tempDir().appendingPathComponent("tools.json")))
    }

    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, layer: UUID) -> Shape {
        Shape(name: "R", layerID: layer, paths: [ShapeFactory.rectangle(Rect2(x: x, y: y, width: w, height: h))])
    }

    /// A project with two 2x1 rectangles at (1,1) and (5,1).
    static func project() -> KerfProject {
        var doc = Document()
        doc.add(rect(1, 1, 2, 1, layer: doc.defaultLayerID))
        doc.add(rect(5, 1, 2, 1, layer: doc.defaultLayerID))
        return KerfProject(document: doc)
    }
}
