import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingSelectionTests {
    let layer = UUID()

    func rect(_ x: Double, _ y: Double, _ w: Double = 2, _ h: Double = 1) -> Shape {
        Shape(layerID: layer, paths: [Path(points: [Vec2(x, y), Vec2(x + w, y), Vec2(x + w, y + h), Vec2(x, y + h)], closed: true)])
    }

    @Test func openVectors() {
        let line = Shape(layerID: layer, paths: [Path(points: [.zero, Vec2(1, 1)], closed: false)])
        let r = rect(0, 0)
        #expect(SelectionQueries.openVectors([r, line]) == [line.id])
    }

    @Test func duplicatesKeepFirstCopy() {
        let a = rect(0, 0), b = rect(5, 5)
        // Same outline as `a`, drawn from another corner in the other direction.
        let c = Shape(layerID: layer, paths: [Path(points: [Vec2(2, 1), Vec2(2, 0), Vec2(0, 0), Vec2(0, 1)], closed: true)])
        let d = rect(0, 0)
        let ids = SelectionQueries.duplicates([a, b, c, d], tolerance: 0.001)
        #expect(ids == [c.id, d.id])
        // A slightly different rectangle is not a duplicate.
        #expect(SelectionQueries.duplicates([a, rect(0, 0, 2.1)], tolerance: 0.001).isEmpty)
        // A circle and its inscribed square share nothing.
        let circle = Shape(layerID: layer, paths: [ShapeFactory.circle(center: Vec2(1, 0.5), radius: 1)])
        #expect(SelectionQueries.duplicates([a, circle], tolerance: 0.001).isEmpty)
    }

    @Test func similarIgnoresPosition() {
        let a = rect(0, 0), b = rect(10, 3), c = rect(0, 0, 3), open = Shape(layerID: layer, paths: [Path(points: [.zero, Vec2(2, 0), Vec2(2, 1), Vec2(0, 1)], closed: false)])
        let ids = SelectionQueries.similar(to: [a], in: [a, b, c, open])
        #expect(ids == [a.id, b.id])
    }

    @Test func invert() {
        let a = rect(0, 0), b = rect(3, 0), c = rect(6, 0)
        #expect(SelectionQueries.inverted([b.id], among: [a, b, c]) == [a.id, c.id])
    }
}
