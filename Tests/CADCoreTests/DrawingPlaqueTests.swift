import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingPlaqueTests {
    let box = Rect2(x: 0, y: 0, width: 10, height: 4)

    @Test func everyStyleFitsTheBoxAndIsConsistent() {
        for style in PlaqueMaker.Style.allCases {
            let paths = PlaqueMaker.make(style, box: box, corner: 1)
            #expect(paths.count == 1, "\(style)")
            let p = paths[0]
            #expect(p.isClosed)
            let b = p.bounds(tolerance: 1e-5)
            #expect(abs(b.width - 10) < 1e-4 && abs(b.height - 4) < 1e-4, "\(style)")
            // Arcs are consistent (start and end on the same circle).
            for (i, seg) in p.segments.enumerated() {
                if case .arc(let to, let c, _) = seg {
                    #expect(abs(p.startOfSegment(i).distance(to: c) - to.distance(to: c)) < 1e-9, "\(style) arc \(i)")
                }
            }
            #expect(VectorValidator.check([Shape(layerID: UUID(), paths: paths)], tolerance: 0.001).isEmpty, "\(style)")
        }
    }

    @Test func cornerAreasAndInnerBorder() {
        let rect = abs(PlaqueMaker.make(.rectangle, box: box, corner: 1)[0].signedArea())
        let notched = abs(PlaqueMaker.make(.notched, box: box, corner: 1)[0].signedArea(tolerance: 1e-5))
        #expect(abs(rect - 40) < 1e-9 && abs(notched - (40 - .pi)) < 1e-3)
        let chamfer = abs(PlaqueMaker.make(.chamfered, box: box, corner: 1)[0].signedArea())
        #expect(abs(chamfer - 38) < 1e-9)
        let double = PlaqueMaker.make(.rounded, box: box, corner: 1, borderInset: 0.25)
        #expect(double.count == 2)
        #expect(abs(double[1].bounds().width - 9.5) < 1e-3)
    }
}
